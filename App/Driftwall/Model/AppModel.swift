import AppKit
import DriftwallCore
import Observation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, explore, popular, library, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .popular: "Popular"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "sparkles.tv"
        case .explore: "magnifyingglass"
        case .popular: "flame"
        case .library: "heart.text.square"
        case .settings: "gearshape"
        }
    }
}

struct DisplayInfo: Identifiable, Hashable {
    let id: DisplayID
    let key: DisplayKey
    var name: String { key.name }
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

/// What the day/night or light/dark picker sheet is choosing.
struct PairRequest: Identifiable {
    enum Kind { case dayNight, lightDark }
    let id = UUID()
    let kind: Kind
    let first: Wallpaper
}

@MainActor
@Observable
final class AppModel {
    static let refreshInterval: Duration = .seconds(24 * 60 * 60)
    static let onboardingKey = "onboardingCompleted"

    // Persisted state
    private(set) var catalog: Catalog = .empty
    private(set) var library = LibraryState()
    private(set) var settings = AppSettings()
    private(set) var assignments = DisplayAssignments()
    private(set) var customWallpapers: [Wallpaper] = []

    // UI state
    var tab: AppTab = .home
    var previewing: Wallpaper?
    var pairRequest: PairRequest?
    var editingPlaylist: Playlist?
    var hoveredCardID: String?
    var isWindowVisible = true
    var showOnboarding = !UserDefaults.standard.bool(forKey: AppModel.onboardingKey)
    var banner: Banner?
    var downloads: [String: Double] = [:]
    private(set) var isRefreshing = false
    private(set) var cacheBytes: Int64 = 0

    // Playback state
    var displays: [DisplayInfo] = []
    var nowPlaying: [DisplayID: String] = [:]
    var pauseReasons: [DisplayID: PauseReason] = [:]
    private(set) var isUserPaused = false
    /// "Play anyway": ignore auto-pause until the user pauses or the app restarts.
    var isAutoPauseOverridden = false
    private(set) var competingApps: [NSRunningApplication] = []

    // Services
    let paths = AppPaths.live
    let engine = WallpaperEngine()
    let monitor = SystemMonitor()
    @ObservationIgnored let cache: VideoCache
    @ObservationIgnored private let catalogService: CatalogService
    @ObservationIgnored private let libraryStore: JSONFileStore<LibraryState>
    @ObservationIgnored private let settingsStore: JSONFileStore<AppSettings>
    @ObservationIgnored private let assignmentsStore: JSONFileStore<DisplayAssignments>
    @ObservationIgnored private let customStore: JSONFileStore<[Wallpaper]>
    @ObservationIgnored var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored var stillShown: [DisplayID: String] = [:]
    @ObservationIgnored var presenting: [DisplayID: (id: String, task: Task<Void, Never>)] = [:]
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var retryAttempt = 0
    /// False until auto-start is on or the user sets a wallpaper this session.
    @ObservationIgnored var playbackEnabled = false
    @ObservationIgnored private var started = false

    init() {
        let paths = AppPaths.live
        libraryStore = JSONFileStore(url: paths.libraryFile)
        settingsStore = JSONFileStore(url: paths.settingsFile)
        assignmentsStore = JSONFileStore(url: paths.assignmentsFile)
        customStore = JSONFileStore(url: paths.customFile)
        let loadedSettings = settingsStore.load() ?? AppSettings()
        settings = loadedSettings
        library = libraryStore.load() ?? LibraryState()
        assignments = assignmentsStore.load() ?? DisplayAssignments()
        customWallpapers = customStore.load() ?? []
        cache = VideoCache(directory: paths.videos, limitBytes: loadedSettings.cacheLimitBytes, downloader: URLSessionVideoDownloader())
        catalogService = CatalogService(
            remoteURL: loadedSettings.effectiveCatalogURL(default: Self.defaultCatalogURL),
            cacheDirectory: paths.caches,
            bundledSeedURL: Bundle.main.url(forResource: "catalog", withExtension: "json"),
            fetcher: URLSessionCatalogFetcher()
        )
    }

    static var defaultCatalogURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "DriftwallCatalogURL") as? String
        return raw.flatMap(URL.init(string:)) ?? URL(string: "https://shorielol.github.io/driftwall/catalog.json")!
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        AppLog.info("Driftwall starting")
        monitor.onStateChange = { [weak self] in self?.updatePause() }
        monitor.onScreensChange = { [weak self] in self?.screensChanged() }
        monitor.onAppearanceChange = { [weak self] in self?.reconcile() }
        monitor.onWake = { [weak self] in
            self?.reconcile()
            Task { await self?.refreshCatalog() }
        }
        engine.onPlaybackFailure = { [weak self] display, id in self?.playbackFailed(display: display, wallpaperID: id) }
        playbackEnabled = settings.autoStartWallpapers
        monitor.start()
        engine.setRate(settings.playbackRate)
        engine.setScaling(settings.scaling)
        refreshDisplays()

        Task {
            catalog = await catalogService.loadCachedOrSeed()
            await protectInUseVideos()
            reconcile()
            await refreshCacheSize()
        }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCatalog()
                try? await Task.sleep(for: Self.refreshInterval)
            }
        }
        if settings.launchAtLogin, !LoginItem.isEnabled {
            _ = LoginItem.set(enabled: true)
        }
    }

    func shutdown() {
        scheduleTask?.cancel()
        refreshLoop?.cancel()
        monitor.stop()
        engine.removeAll()
    }

    // MARK: Onboarding

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        tab = .home
        showOnboarding = false
    }

    func replayOnboarding() {
        previewing = nil
        showOnboarding = true
    }

    // MARK: Lookup

    let originals: [Wallpaper] = OriginalScene.allCases.map(\.wallpaper)

    var allWallpapers: [Wallpaper] { originals + catalog.wallpapers + customWallpapers }

    func wallpaper(id: String) -> Wallpaper? {
        if let scene = OriginalScene(wallpaperID: id) { return scene.wallpaper }
        return catalog.wallpaper(id: id) ?? customWallpapers.first { $0.id == id }
    }

    /// Hero rotation: two Originals lead, then the drop's featured picks.
    var heroWallpapers: [Wallpaper] {
        let picks = catalog.featuredWallpapers.isEmpty ? Array(catalog.wallpapers.prefix(6)) : catalog.featuredWallpapers
        return [OriginalScene.inkMist.wallpaper, OriginalScene.risoTide.wallpaper] + picks.prefix(5)
    }

    func wallpapers(ids: [String]) -> [Wallpaper] { ids.compactMap(wallpaper(id:)) }

    func isNew(_ wallpaper: Wallpaper) -> Bool { catalog.isNew(wallpaper) }

    func isPlaying(_ wallpaper: Wallpaper) -> Bool { nowPlaying.values.contains(wallpaper.id) }

    var currentWallpaper: Wallpaper? {
        displays.lazy.compactMap { self.nowPlaying[$0.id] }.first.flatMap(wallpaper(id:))
    }

    // MARK: Library intents

    func toggleLike(_ wallpaper: Wallpaper) {
        updateLibrary(library.togglingLike(wallpaper.id))
    }

    func toggleMyList(_ wallpaper: Wallpaper) {
        updateLibrary(library.togglingMyList(wallpaper.id))
        show(library.isInMyList(wallpaper.id) ? "Added to My List" : "Removed from My List")
    }

    func savePlaylist(_ playlist: Playlist) {
        updateLibrary(library.upserting(playlist))
    }

    func deletePlaylist(_ playlist: Playlist) {
        updateLibrary(library.removingPlaylist(id: playlist.id))
    }

    func markDropSeen() {
        guard !catalog.dropId.isEmpty, library.lastSeenDropID != catalog.dropId else { return }
        updateLibrary(library.markingDropSeen(catalog.dropId))
    }

    private func updateLibrary(_ next: LibraryState) {
        library = next
        persist { try libraryStore.save(next) }
    }

    // MARK: Apply intents

    func apply(_ wallpaper: Wallpaper, to target: ApplyTarget = .allDisplays) {
        applyRule(.fixed(wallpaper.id), to: target)
        updateLibrary(library.recordingRecent(wallpaper.id))
        refreshCompetingApps()
        if let other = competingApps.first {
            show("\(other.localizedName ?? "Another wallpaper app") is also drawing your desktop. Quit it in Settings → Displays.", isError: true)
        } else if let reason = pauseReasons.values.first, !isAutoPauseOverridden {
            show("Set, but paused: \(reason.label). Use Play Anyway in the toolbar.")
        } else {
            show("Setting “\(wallpaper.title)” as your wallpaper")
        }
    }

    func startPlaylist(_ playlist: Playlist, to target: ApplyTarget = .allDisplays) {
        guard !playlist.wallpaperIDs.isEmpty else {
            show("Add a few wallpapers to the playlist first.", isError: true)
            return
        }
        applyRule(.playlist(playlist, startedAt: Date()), to: target)
        show("Playlist “\(playlist.name)” is rotating")
    }

    func applyPair(kind: PairRequest.Kind, first: Wallpaper, second: Wallpaper, to target: ApplyTarget) {
        let rule: WallpaperRule = switch kind {
        case .dayNight: .dayNight(day: first.id, night: second.id, schedule: settings.dayNightSchedule)
        case .lightDark: .appearance(light: first.id, dark: second.id)
        }
        applyRule(rule, to: target)
        show(kind == .dayNight ? "Day & night wallpapers set" : "Light & dark wallpapers set")
    }

    func applyRule(_ rule: WallpaperRule, to target: ApplyTarget) {
        assignments = assignments.assigning(rule, to: target)
        persistAssignments()
        if isUserPaused { isUserPaused = false }
        playbackEnabled = true
        retryAttempt = 0
        reconcile()
    }

    func clearWallpapers() {
        assignments = assignments.cleared()
        persistAssignments()
        engine.removeAll()
        presenting.values.forEach { $0.task.cancel() }
        presenting = [:]
        retryTask?.cancel()
        nowPlaying = [:]
        stillShown = [:]
        DesktopPicture.restoreOriginals()
        show("Live wallpapers turned off")
    }

    func togglePause() {
        isUserPaused.toggle()
        if isUserPaused { isAutoPauseOverridden = false }
        updatePause()
    }

    func playAnyway() {
        isUserPaused = false
        isAutoPauseOverridden = true
        updatePause()
    }

    /// Other live-wallpaper apps draw at the desktop level too and can hide Driftwall.
    static let knownWallpaperApps = ["wallspace.app", "com.wallpaperengine.mac", "com.plashapp.Plash", "com.sindresorhus.Plash"]

    func refreshCompetingApps() {
        competingApps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.knownWallpaperApps.contains(id) && !$0.isTerminated
        }
    }

    func quitCompetingApps() {
        competingApps.forEach { $0.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshCompetingApps()
            engine.bringToFront()
        }
    }

    /// Skip ahead one item on every display running a playlist.
    func nextInPlaylists() {
        func advanced(_ rule: WallpaperRule) -> WallpaperRule {
            guard case .playlist(let playlist, let startedAt) = rule else { return rule }
            return .playlist(playlist, startedAt: startedAt.addingTimeInterval(-playlist.interval))
        }
        assignments = DisplayAssignments(
            defaultRule: assignments.defaultRule.map(advanced),
            perDisplay: assignments.perDisplay.mapValues(advanced)
        )
        persistAssignments()
        reconcile()
    }

    var hasPlaylistRunning: Bool {
        let rules = [assignments.defaultRule].compactMap { $0 } + Array(assignments.perDisplay.values)
        return rules.contains { if case .playlist = $0 { true } else { false } }
    }

    func download(_ wallpaper: Wallpaper) {
        Task {
            do {
                _ = try await ensureLocal(wallpaper)
                show("“\(wallpaper.title)” is saved for offline use")
            } catch {
                show("Download failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: Custom wallpapers

    static let importableExtensions: Set<String> = ["mp4", "mov", "m4v"]

    func importCustom(from urls: [URL]) {
        let unsupported = urls.filter { !Self.importableExtensions.contains($0.pathExtension.lowercased()) }
        if let first = unsupported.first {
            let hint = first.pathExtension.lowercased() == "webm" ? " WebM can't play on macOS; convert it to MP4 first." : ""
            show("“\(first.lastPathComponent)” isn't a supported video.\(hint)", isError: true)
        }
        let urls = urls.filter { Self.importableExtensions.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        Task {
            for url in urls {
                do {
                    let wallpaper = try await CustomImporter.importVideo(
                        at: url, videosDirectory: paths.customVideos, postersDirectory: paths.customPosters
                    )
                    customWallpapers.append(wallpaper)
                    persist { try customStore.save(customWallpapers) }
                    if !wallpaper.meetsMinimumResolution {
                        show("Imported “\(wallpaper.title)”, but it's \(wallpaper.width)×\(wallpaper.height), below landscape 1080p, so it may look soft.", isError: true)
                    } else {
                        show("Imported “\(wallpaper.title)” in \(wallpaper.resolutionLabel)")
                    }
                } catch {
                    show(error.localizedDescription, isError: true)
                }
            }
            await protectInUseVideos()
            await refreshCacheSize()
        }
    }

    /// Wallspace downloads on this Mac that haven't been imported yet.
    var wallspaceCandidates: [WallspaceImporter.Candidate] {
        let imported = Set(customWallpapers.filter { $0.description == WallspaceImporter.note }.map(\.title))
        return WallspaceImporter.discover().filter { !imported.contains($0.title) }
    }

    func importFromWallspace() {
        let candidates = wallspaceCandidates
        guard !candidates.isEmpty else {
            show("No new Wallspace downloads found on this Mac.")
            return
        }
        Task {
            var count = 0
            for candidate in candidates {
                do {
                    let wallpaper = try await CustomImporter.importVideo(
                        at: candidate.file, videosDirectory: paths.customVideos, postersDirectory: paths.customPosters,
                        title: candidate.title, category: "Imported", note: WallspaceImporter.note
                    )
                    customWallpapers.append(wallpaper)
                    count += 1
                } catch {
                    AppLog.error("Wallspace import failed for \(candidate.title): \(error.localizedDescription)")
                }
            }
            persist { try customStore.save(customWallpapers) }
            show(count == 0 ? "Couldn't import those videos." : "Imported \(count) wallpaper\(count == 1 ? "" : "s") from Wallspace")
        }
    }

    func removeCustom(_ wallpaper: Wallpaper) {
        customWallpapers.removeAll { $0.id == wallpaper.id }
        persist { try customStore.save(customWallpapers) }
        try? FileManager.default.removeItem(at: wallpaper.videoURL)
        try? FileManager.default.removeItem(at: wallpaper.posterURL)
        reconcile()
    }

    // MARK: Catalog

    func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let previousDrop = catalog.dropId
        switch await catalogService.refresh() {
        case .updated(let updated):
            catalog = updated
            await handleDropChange(from: previousDrop)
            reconcile()
        case .notModified:
            break
        case .failed(let reason):
            AppLog.info("Catalog refresh skipped: \(reason)")
        }
    }

    private func handleDropChange(from previousDrop: String) async {
        guard library.lastSeenDropID != nil else {
            markDropSeen()
            return
        }
        guard catalog.hasNewDrop(comparedTo: library.lastSeenDropID), catalog.dropId != previousDrop || previousDrop.isEmpty else { return }
        AppLog.info("New drop \(catalog.dropId)")
        if settings.notifyNewDrops {
            await DropNotifier.announce(dropID: catalog.dropId, count: catalog.latestDropWallpapers.count)
        }
        if settings.rotateLatestDrop { startLatestDropRotation() }
    }

    func startLatestDropRotation() {
        let ids = catalog.latestDropWallpapers.map(\.id)
        guard !ids.isEmpty else { return }
        let playlist = Playlist(name: "Fresh Drop", wallpaperIDs: ids, interval: settings.rotationInterval.seconds, shuffle: true)
        applyRule(.playlist(playlist, startedAt: Date()), to: .allDisplays)
    }

    // MARK: Settings

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.updateSettings { $0[keyPath: keyPath] = value } })
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        let old = settings
        var next = settings
        change(&next)
        next = AppSettings(
            launchAtLogin: next.launchAtLogin, autoStartWallpapers: next.autoStartWallpapers, autoPause: next.autoPause,
            playbackRate: next.playbackRate, scaling: next.scaling, cacheLimitGB: next.cacheLimitGB,
            notifyNewDrops: next.notifyNewDrops, rotateLatestDrop: next.rotateLatestDrop,
            rotationInterval: next.rotationInterval, setStaticFallback: next.setStaticFallback,
            catalogURLOverride: next.catalogURLOverride, dayNightSchedule: next.dayNightSchedule
        )
        settings = next
        persist { try settingsStore.save(next) }
        applySettingsChange(from: old, to: next)
    }

    private func applySettingsChange(from old: AppSettings, to new: AppSettings) {
        if old.playbackRate != new.playbackRate { engine.setRate(new.playbackRate) }
        if old.scaling != new.scaling { engine.setScaling(new.scaling) }
        if old.autoPause != new.autoPause { updatePause() }
        if old.cacheLimitGB != new.cacheLimitGB {
            Task {
                await cache.setLimit(bytes: new.cacheLimitBytes)
                await refreshCacheSize()
            }
        }
        if old.launchAtLogin != new.launchAtLogin, let problem = LoginItem.set(enabled: new.launchAtLogin) {
            show(problem, isError: true)
        }
        if old.notifyNewDrops != new.notifyNewDrops, new.notifyNewDrops {
            Task { _ = await DropNotifier.requestPermission() }
        }
        if new.rotateLatestDrop, !old.rotateLatestDrop || old.rotationInterval != new.rotationInterval {
            startLatestDropRotation()
        }
        if old.dayNightSchedule != new.dayNightSchedule { refreshDayNightSchedules(new.dayNightSchedule) }
        if new.setStaticFallback, !old.setStaticFallback {
            stillShown = [:]
            reconcile()
        } else if !new.setStaticFallback, old.setStaticFallback {
            stillShown = [:]
            DesktopPicture.restoreOriginals()
        }
    }

    private func refreshDayNightSchedules(_ schedule: DayNightSchedule) {
        func updated(_ rule: WallpaperRule) -> WallpaperRule {
            guard case .dayNight(let day, let night, _) = rule else { return rule }
            return .dayNight(day: day, night: night, schedule: schedule)
        }
        assignments = DisplayAssignments(
            defaultRule: assignments.defaultRule.map(updated),
            perDisplay: assignments.perDisplay.mapValues(updated)
        )
        persistAssignments()
        reconcile()
    }

    // MARK: Storage

    func refreshCacheSize() async {
        cacheBytes = await cache.totalBytes()
    }

    func clearCache() {
        Task {
            await protectInUseVideos()
            await cache.clear()
            await ImageLoader.shared.clearDisk()
            await refreshCacheSize()
            show("Cache cleared. Wallpapers in use were kept.")
        }
    }

    func protectInUseVideos() async {
        let ids = Set(assignments.referencedIDs).union(customWallpapers.map(\.id))
        await cache.protect(ids)
    }

    // MARK: Deep links

    func open(url: URL) {
        guard url.scheme == "driftwall", url.host() == "wallpaper" else { return }
        let id = url.lastPathComponent
        guard (try? VideoCache.fileName(for: id)) != nil, let wallpaper = wallpaper(id: id) else {
            show("That wallpaper link isn't in the catalog.", isError: true)
            return
        }
        previewing = wallpaper
        NSApp.activate()
    }

    // MARK: Helpers

    func show(_ message: String, isError: Bool = false) {
        let next = Banner(message: message, isError: isError)
        banner = next
        if isError { AppLog.error(message) }
        Task {
            try? await Task.sleep(for: .seconds(isError ? 6 : 3.5))
            if banner == next { banner = nil }
        }
    }

    func persistAssignments() {
        persist { try assignmentsStore.save(assignments) }
        Task { await protectInUseVideos() }
    }

    private func persist(_ write: () throws -> Void) {
        do {
            try write()
        } catch {
            AppLog.error("Saving failed: \(error.localizedDescription)")
        }
    }
}
