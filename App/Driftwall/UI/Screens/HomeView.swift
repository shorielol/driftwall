import DriftwallCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if model.catalog.wallpapers.isEmpty {
                EmptyState(
                    title: "Gathering wallpapers",
                    message: "Driftwall is fetching the latest drop. Check your connection if this takes more than a moment.",
                    actionTitle: "Try Again"
                ) { Task { await model.refreshCatalog() } }
                .padding(.top, 140)
            } else {
                LazyVStack(alignment: .leading, spacing: Theme.Space.section) {
                    HeroCarousel()
                    WallpaperRow(
                        title: "Driftwall Originals",
                        subtitle: "Rendered live on your Mac, sharp at any resolution",
                        wallpapers: model.originals
                    )
                    WallpaperRow(title: "Fresh Drop", subtitle: dropSubtitle, wallpapers: model.catalog.latestDropWallpapers) {
                        DropCountdown()
                    }
                    WallpaperRow(title: "Recently Used", wallpapers: model.wallpapers(ids: model.library.recents))
                    WallpaperRow(title: "My List", wallpapers: model.wallpapers(ids: model.library.myList))
                    WallpaperRow(title: "Popular", wallpapers: Array(CatalogQuery(sort: .popular).apply(to: model.catalog.wallpapers).prefix(20)))
                    ForEach(model.catalog.categories, id: \.self) { category in
                        WallpaperRow(title: category, wallpapers: CatalogQuery(category: category).apply(to: model.catalog.wallpapers))
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .scrollIndicators(.never)
        .onAppear { model.markDropSeen() }
    }

    private var dropSubtitle: String? {
        model.catalog.dropId.isEmpty ? nil : "Landed \(DropDate.short(model.catalog.dropId))"
    }
}

struct DropCountdown: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let days = model.catalog.daysUntilNextDrop(from: Date()) {
            HStack(spacing: 8) {
                LiquidGlassOrb(size: 16, isAnimating: false)
                Text(days == 0 ? "Next drop today" : "Next drop in \(days) day\(days == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassCapsule()
            .help("New wallpapers arrive every three weeks")
        }
    }
}

struct HeroCarousel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive
    @State private var index = 0
    @State private var isHovering = false
    @State private var isTitleHovered = false

    private static let advanceInterval: Duration = .seconds(9)
    private static let height: CGFloat = 580

    private var featured: [Wallpaper] { model.heroWallpapers }

    var body: some View {
        let items = featured
        if !items.isEmpty {
            let current = items[index % items.count]
            ZStack(alignment: .bottomLeading) {
                backdrop(current)
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, Theme.ink], startPoint: .center, endPoint: .bottom)
                details(current)
                    .padding(.horizontal, Theme.Space.gutter + 8)
                    .padding(.bottom, 54)
                    .id(current.id)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
            .overlay(alignment: .bottomTrailing) {
                FanGallery(wallpapers: items.filter { $0.id != current.id }.prefix(4).map { $0 }, selectedID: nil) { picked in
                    if let position = items.firstIndex(of: picked) {
                        withAnimation(Theme.Motion.standard) { index = position }
                    }
                }
                .padding(.trailing, Theme.Space.gutter)
                .padding(.bottom, 40)
            }
            .overlay(alignment: .bottom) { pageDots(count: items.count) }
            .frame(height: Self.height)
            .clipped()
            .onHover { isHovering = $0 }
            .task(id: index) { await autoAdvance(count: items.count) }
        }
    }

    private func backdrop(_ wallpaper: Wallpaper) -> some View {
        Color.black
            .overlay {
                ZStack {
                    WallpaperPoster(wallpaper: wallpaper)
                    WallpaperMotion(wallpaper: wallpaper, isPlaying: model.previewing == nil && animationsActive)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipped()
            .id(wallpaper.id)
            .transition(.opacity)
    }

    private func details(_ wallpaper: Wallpaper) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.auroraGradient).frame(width: 7, height: 7)
                Text(wallpaper.isOriginal ? "DRIFTWALL ORIGINAL · RENDERED LIVE" : model.isNew(wallpaper) ? "FRESH DROP · \(DropDate.short(model.catalog.dropId).uppercased())" : wallpaper.category.uppercased())
                    .font(Theme.Typeface.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(Theme.textSecondary)
            }
            RefractedTitle(text: wallpaper.title, size: 52, isHighlighted: isTitleHovered)
                .frame(maxWidth: 640, alignment: .leading)
                .onHover { hovering in isTitleHovered = hovering }
            if !wallpaper.description.isEmpty {
                Text(wallpaper.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 540, alignment: .leading)
            }
            HStack(spacing: 10) {
                WallpaperMeta(wallpaper: wallpaper)
                Text("· by \(wallpaper.author)").font(Theme.Typeface.caption).foregroundStyle(Theme.textTertiary)
            }
            GlassGroup(spacing: 8) {
                HStack(spacing: 10) {
                    ApplyControl(wallpaper: wallpaper)
                    GlassButton(title: "Preview", systemImage: "arrow.up.left.and.arrow.down.right") { model.previewing = wallpaper }
                    GlassButton(title: nil, systemImage: model.library.isLiked(wallpaper.id) ? "heart.fill" : "heart",
                                isOn: model.library.isLiked(wallpaper.id), help: "Like") { model.toggleLike(wallpaper) }
                    GlassButton(title: nil, systemImage: model.library.isInMyList(wallpaper.id) ? "checkmark" : "plus",
                                help: "My List") { model.toggleMyList(wallpaper) }
                }
            }
            .padding(.top, 6)
        }
    }

    private func pageDots(count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index % count ? Color.white : Color.white.opacity(0.3))
                    .frame(width: dot == index % count ? 22 : 6, height: 6)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Theme.Motion.standard) { index = dot } }
                    .accessibilityLabel("Featured \(dot + 1) of \(count)")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .animation(Theme.Motion.standard, value: index)
        .padding(.bottom, 18)
    }

    private func autoAdvance(count: Int) async {
        guard count > 1, !reduceMotion else { return }
        try? await Task.sleep(for: Self.advanceInterval)
        guard !Task.isCancelled, !isHovering, model.previewing == nil else { return }
        withAnimation(Theme.Motion.standard) { index = (index + 1) % count }
    }
}
