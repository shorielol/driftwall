import AppKit
import DriftwallCore
import SwiftUI

@main
struct DriftwallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Driftwall", id: "main") {
            RootView()
                .environment(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands { DriftwallCommands(model: delegate.model) }

        MenuBarExtra {
            MenuBarView()
                .environment(delegate.model)
        } label: {
            Image(systemName: delegate.model.isUserPaused ? "pause.rectangle" : "sparkles.tv")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    /// Wallpapers keep playing after the browser window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}

struct DriftwallCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Wallpaper") {
            Button(model.isUserPaused ? "Resume" : "Pause") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Next in Playlist") { model.nextInPlaylists() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!model.hasPlaylistRunning)
            Divider()
            Button("Check for New Drop") { Task { await model.refreshCatalog() } }
                .keyboardShortcut("r", modifiers: .command)
            Button("Turn Off Live Wallpapers") { model.clearWallpapers() }
        }
        CommandGroup(replacing: .help) {
            Button("Welcome Tour") { model.replayOnboarding() }
            Link("Driftwall on GitHub", destination: AuthorInfo.repositoryURL)
        }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.nowPlaying.isEmpty {
                ForEach(model.displays) { display in
                    HStack {
                        Image(systemName: "display").foregroundStyle(.secondary)
                        Text(display.name).lineLimit(1)
                        Spacer()
                        Text(model.nowPlaying[display.id].flatMap(model.wallpaper(id:))?.title ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                }
            }
            HStack(spacing: 8) {
                if !model.nowPlaying.isEmpty {
                    GlassButton(title: model.isUserPaused ? "Resume" : "Pause", systemImage: model.isUserPaused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                }
                if model.hasPlaylistRunning {
                    GlassButton(title: nil, systemImage: "forward.fill", help: "Next") { model.nextInPlaylists() }
                }
                Spacer()
                GlassButton(title: "Open", systemImage: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
            Divider()
            HStack {
                DropCountdown()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 330)
        .tint(Theme.violet)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var header: some View {
        if let current = model.currentWallpaper {
            HStack(spacing: 12) {
                WallpaperPoster(wallpaper: current)
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    let reasons = Set(model.pauseReasons.values.map(\.label))
                    Text(reasons.isEmpty ? "Playing" : reasons.sorted().joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(reasons.isEmpty ? Theme.teal : Theme.amber)
                }
            }
        } else {
            HStack(spacing: 12) {
                LiquidGlassOrb(size: 40)
                VStack(alignment: .leading) {
                    Text("Driftwall").font(.headline)
                    Text("No live wallpaper yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
