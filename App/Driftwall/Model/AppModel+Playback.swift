import AppKit
import DriftwallCore

/// Turns rules into what each display shows: resolve → download if needed → play → schedule the next change.
extension AppModel {
    func refreshDisplays() {
        displays = NSScreen.screens.map { DisplayInfo(id: $0.displayID, key: $0.displayKey) }
    }

    func screensChanged() {
        refreshDisplays()
        engine.reframe(screens: NSScreen.screens)
        reconcile()
    }

    /// Make every display match its rule right now.
    func reconcile() {
        refreshDisplays()
        guard playbackEnabled else { return }
        let now = Date()
        let isDark = SystemMonitor.systemIsDark()
        var desired: [DisplayID: String] = [:]

        for screen in NSScreen.screens {
            let display = screen.displayID
            guard let rule = assignments.rule(for: screen.displayKey),
                  let id = rule.resolve(at: now, isDarkAppearance: isDark),
                  let wallpaper = wallpaper(id: id) else {
                presenting.removeValue(forKey: display)?.task.cancel()
                engine.remove(display: display)
                continue
            }
            desired[display] = id
            guard engine.wallpaperID(on: display) != id, presenting[display]?.id != id else { continue }
            presenting.removeValue(forKey: display)?.task.cancel()
            present(wallpaper, on: screen)
        }

        nowPlaying = desired
        scheduleNextChange(after: now)
        updatePause()
        engine.bringToFront()
        refreshCompetingApps()
    }

    private func present(_ wallpaper: Wallpaper, on screen: NSScreen) {
        let display = screen.displayID
        if let scene = wallpaper.originalScene {
            engine.show(.scene(scene), wallpaperID: wallpaper.id, on: screen, paused: pauseReason(for: display) != nil)
            return
        }
        let task = Task {
            defer { if presenting[display]?.id == wallpaper.id { presenting[display] = nil } }
            do {
                let local = try await ensureLocal(wallpaper)
                guard !Task.isCancelled, nowPlaying[display] == wallpaper.id else { return }
                let paused = pauseReason(for: display) != nil
                engine.show(url: local, wallpaperID: wallpaper.id, on: screen, paused: paused)
                applyStill(for: wallpaper, local: local, on: screen)
                retryAttempt = 0
                await refreshCacheSize()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                show("Couldn't load “\(wallpaper.title)”. Retrying soon.", isError: true)
                AppLog.error("Present \(wallpaper.id) failed: \(error.localizedDescription)")
                scheduleRetry()
            }
        }
        presenting[display] = (wallpaper.id, task)
    }

    /// Bounded exponential backoff: 15 s, 30 s, 60 s … up to 10 minutes.
    func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(600.0, 15.0 * pow(2.0, Double(retryAttempt)))
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    /// A downloaded file wouldn't play: drop it so the next attempt downloads a fresh copy.
    func playbackFailed(display: DisplayID, wallpaperID: String) {
        AppLog.error("Playback failed for \(wallpaperID) on display \(display)")
        if let wallpaper = wallpaper(id: wallpaperID), wallpaper.source != "custom" {
            Task { await cache.remove(id: wallpaperID) }
        }
        show("“\(wallpaper(id: wallpaperID)?.title ?? "That wallpaper")” couldn't play. Trying again.", isError: true)
        scheduleRetry()
    }

    /// Local file URL for a wallpaper, downloading the 4K master with progress if needed.
    func ensureLocal(_ wallpaper: Wallpaper) async throws -> URL {
        if wallpaper.isOriginal { return wallpaper.videoURL }
        if wallpaper.source == "custom" {
            guard FileManager.default.fileExists(atPath: wallpaper.videoURL.path(percentEncoded: false)) else { throw CocoaError(.fileNoSuchFile) }
            return wallpaper.videoURL
        }
        if let local = await cache.localURL(for: wallpaper.id) { return local }
        let ownsProgress = downloads[wallpaper.id] == nil
        if ownsProgress { downloads[wallpaper.id] = 0 }
        defer { if ownsProgress { downloads[wallpaper.id] = nil } }
        let id = wallpaper.id
        return try await cache.download(wallpaper) { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.downloads[id] != nil else { return }
                self.downloads[id] = fraction
            }
        }
    }

    private func applyStill(for wallpaper: Wallpaper, local: URL, on screen: NSScreen) {
        let display = screen.displayID
        guard settings.setStaticFallback, stillShown[display] != wallpaper.id else { return }
        stillShown[display] = wallpaper.id
        let directory = paths.stills
        Task {
            do {
                let still = try await DesktopPicture.still(for: local, id: wallpaper.id, directory: directory)
                DesktopPicture.apply(still, to: screen)
            } catch {
                AppLog.error("Still frame failed for \(wallpaper.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Pausing

    func pauseReason(for display: DisplayID) -> PauseReason? {
        let reason = AutoPausePolicy.reason(display: display, state: monitor.snapshot(userPaused: isUserPaused), settings: settings.autoPause)
        if isAutoPauseOverridden, reason != .user, reason != .displayAsleep { return nil }
        return reason
    }

    func updatePause() {
        var reasons: [DisplayID: PauseReason] = [:]
        for display in engine.activeDisplayIDs {
            let reason = pauseReason(for: display)
            engine.setPaused(reason != nil, on: display)
            reasons[display] = reason
        }
        pauseReasons = reasons
    }

    // MARK: Scheduling

    private func scheduleNextChange(after now: Date) {
        scheduleTask?.cancel()
        let rules = NSScreen.screens.compactMap { assignments.rule(for: $0.displayKey) }
        guard let next = rules.compactMap({ $0.nextChange(after: now) }).min() else { return }
        prefetch(rules: rules, at: next)
        let delay = max(1, next.timeIntervalSince(now))
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    /// Download what will be shown next so the switch is instant.
    private func prefetch(rules: [WallpaperRule], at date: Date) {
        let isDark = SystemMonitor.systemIsDark()
        let upcoming = Set(rules.compactMap { $0.resolve(at: date.addingTimeInterval(1), isDarkAppearance: isDark) })
        for id in upcoming {
            guard let wallpaper = wallpaper(id: id) else { continue }
            Task { _ = try? await ensureLocal(wallpaper) }
        }
    }
}
