import DriftwallCore
import SwiftUI

/// 16:9 poster card. Hover lifts it and, after a short dwell, streams the live preview in place.
struct WallpaperCard: View {
    let wallpaper: Wallpaper
    var width: CGFloat?

    @Environment(AppModel.self) private var model
    @State private var isHovering = false
    @State private var dwellTask: Task<Void, Never>?

    private static let previewDwell: Duration = .milliseconds(450)

    private var isPreviewing: Bool { model.hoveredCardID == wallpaper.id && isHovering }

    var body: some View {
        // A fixed 16:9 frame; artwork is an overlay so live scenes can't collapse the card.
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(width: width)
            .overlay {
                ZStack {
                    WallpaperPoster(wallpaper: wallpaper)
                    if isPreviewing {
                        WallpaperMotion(wallpaper: wallpaper)
                            .transition(.opacity)
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) { info }
            .overlay(alignment: .topLeading) { badges }
            .overlay(alignment: .topTrailing) { progress }
            .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isHovering ? Color.white.opacity(0.55) : Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.55 : 0.3), radius: isHovering ? 22 : 10, y: isHovering ? 12 : 5)
        .scaleEffect(isHovering ? 1.035 : 1)
        .animation(Theme.Motion.lively, value: isHovering)
        .animation(Theme.Motion.fade, value: isPreviewing)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .onHover(perform: hover)
        .onTapGesture { model.previewing = wallpaper }
        .contextMenu { WallpaperActions(wallpaper: wallpaper) }
        .onDisappear { dwellTask?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(wallpaper.title), \(wallpaper.category), \(wallpaper.resolutionLabel)"))
        .accessibilityHint(Text("Opens a full-screen preview"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.previewing = wallpaper }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(wallpaper.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            WallpaperMeta(wallpaper: wallpaper)
        }
        .padding(12)
    }

    private var badges: some View {
        HStack(spacing: 5) {
            if model.isNew(wallpaper) { NewBadge() }
            if model.isPlaying(wallpaper) {
                NowPlayingIndicator(isPaused: model.isUserPaused)
            }
            if model.library.isLiked(wallpaper.id) {
                Badge(text: "", systemImage: "heart.fill", tint: Theme.rose)
            }
        }
        .padding(9)
    }

    @ViewBuilder private var progress: some View {
        if let fraction = model.downloads[wallpaper.id] {
            ProgressRing(progress: fraction)
                .frame(width: 18, height: 18)
                .padding(6)
                .background(.black.opacity(0.6), in: Circle())
                .padding(8)
        }
    }

    private func hover(_ hovering: Bool) {
        isHovering = hovering
        dwellTask?.cancel()
        guard hovering else {
            if model.hoveredCardID == wallpaper.id { model.hoveredCardID = nil }
            return
        }
        dwellTask = Task {
            try? await Task.sleep(for: Self.previewDwell)
            guard !Task.isCancelled, isHovering else { return }
            model.hoveredCardID = wallpaper.id
        }
    }
}

/// Shared actions for context menus and the preview's overflow menu.
struct WallpaperActions: View {
    let wallpaper: Wallpaper
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Set on All Displays", systemImage: "display.2") { model.apply(wallpaper) }
        if model.displays.count > 1 {
            Menu("Set on Display") {
                ForEach(model.displays) { display in
                    Button(display.name) { model.apply(wallpaper, to: .display(display.key)) }
                }
            }
        }
        Divider()
        Button(model.library.isLiked(wallpaper.id) ? "Unlike" : "Like", systemImage: "heart") { model.toggleLike(wallpaper) }
        Button(model.library.isInMyList(wallpaper.id) ? "Remove from My List" : "Add to My List", systemImage: "plus") {
            model.toggleMyList(wallpaper)
        }
        if !wallpaper.isOriginal, wallpaper.source != "custom" {
            Button("Download \(wallpaper.resolutionLabel)", systemImage: "arrow.down.circle") { model.download(wallpaper) }
        }
        Divider()
        Button("Use for Day & Night…", systemImage: "sun.and.horizon") {
            model.pairRequest = PairRequest(kind: .dayNight, first: wallpaper)
        }
        Button("Use for Light & Dark…", systemImage: "circle.lefthalf.filled") {
            model.pairRequest = PairRequest(kind: .lightDark, first: wallpaper)
        }
        if wallpaper.source != "custom", !wallpaper.isOriginal {
            Divider()
            Button("Copy Link", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("driftwall://wallpaper/\(wallpaper.id)", forType: .string)
            }
            Link(destination: wallpaper.sourcePageURL) { Label("View on \(wallpaper.sourceName)", systemImage: "safari") }
        }
    }
}
