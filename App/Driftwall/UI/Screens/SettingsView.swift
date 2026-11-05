import DriftwallCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Driftwall runs quietly; these let you tune how") { EmptyView() }
                // Two independent columns, so a tall card never leaves a gap beside it.
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        general
                        autoPause
                        dayNight
                        displays
                    }
                    VStack(spacing: 18) {
                        playback
                        drops
                        storage
                        about
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
            }
            .padding(.bottom, 48)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $showingLog) { LogSheet() }
        .task {
            model.refreshCompetingApps()
            await model.refreshCacheSize()
        }
    }

    private var general: some View {
        SettingsCard(title: "General", symbol: "switch.2") {
            Toggle("Launch Driftwall at login", isOn: model.binding(\.launchAtLogin))
            Toggle("Start live wallpapers automatically", isOn: model.binding(\.autoStartWallpapers))
            Toggle("Match the lock screen with a still frame", isOn: model.binding(\.setStaticFallback))
            Text("Driftwall sets a still from your live wallpaper as the desktop picture, so the lock screen and Mission Control match.")
                .settingsFootnote()
            Toggle("Animate the lock screen (experimental)", isOn: model.binding(\.animateLockScreen))
                .disabled(!model.lockScreen.isAvailable)
            Text(model.lockScreen.isAvailable
                 ? "Fades your live wallpaper in on the lock screen after a few idle seconds and hides it when you touch the keyboard or trackpad. macOS has no public way to do this, so Driftwall uses a private system API that an update could break. Keep the still frame on as the fallback."
                 : "Not available on this version of macOS.")
                .settingsFootnote()
            Toggle("Offer new videos from Downloads as wallpapers", isOn: model.binding(\.watchDownloads))
            Text("When an MP4, MOV or M4V finishes downloading, Driftwall asks if you want to use it. Imports stay on this Mac. macOS will ask once for access to Downloads.")
                .settingsFootnote()
        }
    }

    private var playback: some View {
        SettingsCard(title: "Playback", symbol: "play.rectangle") {
            LabeledContent("Speed") {
                HStack {
                    Slider(value: model.binding(\.playbackRate), in: AppSettings.playbackRateRange, step: 0.05)
                        .frame(width: 200)
                    Text(model.settings.playbackRate, format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 40)
                    Text("×")
                }
            }
            LabeledContent("Scaling") {
                GlassSegmented(options: VideoScaling.allCases.map { ($0, $0.label) }, selection: model.binding(\.scaling))
            }
            Text("Video is muted and hardware-decoded. Paused wallpapers use almost no power.").settingsFootnote()
        }
    }

    private var autoPause: some View {
        SettingsCard(title: "Auto-Pause", symbol: "pause.circle") {
            Toggle("When an app is full screen (only that display)", isOn: model.binding(\.autoPause.onFullscreen))
            Toggle("In Low Power Mode", isOn: model.binding(\.autoPause.onLowPowerMode))
            Toggle("When battery is below \(AutoPauseSettings.lowBatteryThreshold)%", isOn: model.binding(\.autoPause.onLowBattery))
            Toggle("Whenever running on battery", isOn: model.binding(\.autoPause.onBatteryPower))
            if !model.pauseReasons.isEmpty {
                Text("Paused now: \(Set(model.pauseReasons.values.map(\.label)).sorted().joined(separator: ", "))").settingsFootnote()
            }
        }
    }

    private var drops: some View {
        SettingsCard(title: "Fresh Drops", symbol: "sparkles") {
            LabeledContent("Current drop") {
                Text(model.catalog.dropId.isEmpty ? "—" : DropDate.short(model.catalog.dropId))
            }
            LabeledContent("Next drop") {
                if let days = model.catalog.daysUntilNextDrop(from: Date()) {
                    Text(days == 0 ? "Today" : "In \(days) days")
                } else {
                    Text("—")
                }
            }
            Toggle("Notify me when a drop lands", isOn: model.binding(\.notifyNewDrops))
            Toggle("Rotate through the latest drop", isOn: model.binding(\.rotateLatestDrop))
            if model.settings.rotateLatestDrop {
                Picker("Rotation", selection: model.binding(\.rotationInterval)) {
                    ForEach(RotationInterval.allCases) { Text($0.label).tag($0) }
                }
            }
            HStack {
                Button("Check Now") { Task { await model.refreshCatalog() } }
                    .disabled(model.isRefreshing)
                if model.isRefreshing { ProgressView().controlSize(.small) }
            }
            DisclosureGroup("Advanced") {
                TextField("Custom catalog URL (https)", text: model.binding(\.catalogURLOverride))
                    .textFieldStyle(.roundedBorder)
                Text("Applies after relaunch. Leave empty to use the official catalog.").settingsFootnote()
            }
        }
    }

    private var dayNight: some View {
        SettingsCard(title: "Day & Night", symbol: "sun.and.horizon") {
            ScheduleEditor()
            Text("Set a pair from any wallpaper's ⋯ menu → Use for Day & Night.").settingsFootnote()
        }
    }

    private var storage: some View {
        SettingsCard(title: "Storage", symbol: "internaldrive") {
            LabeledContent("Downloaded wallpapers") {
                Text(ByteCountFormatter.string(fromByteCount: model.cacheBytes, countStyle: .file)).monospacedDigit()
            }
            Stepper(value: model.binding(\.cacheLimitGB), in: AppSettings.cacheLimitRange) {
                Text("Keep up to \(model.settings.cacheLimitGB) GB")
            }
            HStack {
                Button("Clear Cache") { model.clearCache() }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.paths.videos]) }
            }
            Text("Wallpapers you're using are never removed.").settingsFootnote()
        }
    }

    private var displays: some View {
        SettingsCard(title: "Displays", symbol: "display.2") {
            if !model.competingApps.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    Text("\(model.competingApps.compactMap(\.localizedName).joined(separator: ", ")) is also drawing your desktop and can hide Driftwall.")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Quit It") { model.quitCompetingApps() }
                }
            }
            ForEach(model.displays) { display in
                LabeledContent(display.name) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.nowPlaying[display.id].flatMap(model.wallpaper(id:))?.title ?? "Not set")
                        if let reason = model.pauseReasons[display.id] {
                            Text(reason.label).font(.caption).foregroundStyle(Theme.amber)
                        } else if let rule = model.assignments.rule(for: display.key) {
                            Text(rule.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("Turn Off Live Wallpapers", role: .destructive) { model.clearWallpapers() }
                .disabled(model.nowPlaying.isEmpty)
        }
    }

    private var about: some View {
        SettingsCard(title: "About", symbol: "info.circle") {
            LabeledContent("Made by") {
                Link("\(AuthorInfo.name) \(AuthorInfo.handle)", destination: AuthorInfo.profileURL)
            }
            LabeledContent("Version") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
            Text("Space loops come from NASA (public domain), ESA/Webb and ESA/Hubble (CC BY 4.0). Film loops are cut from Blender open movies (CC BY). Each preview credits its source and links to the original.")
                .settingsFootnote()
            HStack {
                Link("Source on GitHub", destination: URL(string: "https://github.com/shorielol/driftwall")!)
                Spacer()
                Button("Show Welcome Tour") { model.replayOnboarding() }
                Button("View Log") { showingLog = true }
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(Theme.Typeface.title(16))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 10) { content }
                .toggleStyle(.switch)
                .controlSize(.regular)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: Theme.Radius.panel)
    }
}

extension Text {
    func settingsFootnote() -> some View {
        font(.system(size: 11)).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = "Loading…"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Driftwall Log").font(.headline)
                Spacer()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.live.logFile]) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 760, height: 520)
        .task { text = await AppLog.tail() }
    }
}
