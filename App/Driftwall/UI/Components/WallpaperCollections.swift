import DriftwallCore
import SwiftUI

struct SectionHeader<Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(Theme.Typeface.title(21))
                .displayTracking(21)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(Theme.Typeface.body).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Horizontal carousel with paging chevrons that appear on hover.
struct WallpaperRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    let wallpapers: [Wallpaper]
    var cardWidth: CGFloat = 288
    @ViewBuilder var accessory: Accessory

    @State private var position = ScrollPosition(idType: String.self)
    @State private var index = 0
    @State private var isHovering = false

    private let pageSize = 3

    var body: some View {
        if !wallpapers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title, subtitle: subtitle) { accessory }
                    .padding(.horizontal, Theme.Space.gutter)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Space.card) {
                        ForEach(wallpapers) { wallpaper in
                            WallpaperCard(wallpaper: wallpaper, width: cardWidth)
                                .id(wallpaper.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.never)
                .scrollPosition($position, anchor: .leading)
                .scrollTargetBehavior(.viewAligned)
                .overlay { pager }
                .onHover { hovering in withAnimation(Theme.Motion.fade) { isHovering = hovering } }
            }
        }
    }

    private var pager: some View {
        HStack {
            chevron("chevron.left", label: "Scroll back", enabled: index > 0) { step(-pageSize) }
            Spacer()
            chevron("chevron.right", label: "Scroll forward", enabled: index + pageSize < wallpapers.count) { step(pageSize) }
        }
        .padding(.horizontal, 10)
        .opacity(isHovering ? 1 : 0)
    }

    private func chevron(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        GlassButton(title: nil, systemImage: symbol, help: label, action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0)
    }

    private func step(_ delta: Int) {
        index = min(max(0, index + delta), max(0, wallpapers.count - 1))
        withAnimation(Theme.Motion.standard) {
            position.scrollTo(id: wallpapers[index].id, anchor: .leading)
        }
    }
}

extension WallpaperRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, wallpapers: [Wallpaper], cardWidth: CGFloat = 288) {
        self.init(title: title, subtitle: subtitle, wallpapers: wallpapers, cardWidth: cardWidth) { EmptyView() }
    }
}

struct WallpaperGrid: View {
    let wallpapers: [Wallpaper]

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 18)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(wallpapers) { WallpaperCard(wallpaper: $0) }
        }
        .padding(.horizontal, Theme.Space.gutter)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            LiquidGlassOrb(size: 96)
            Text(title).font(Theme.Typeface.title(20)).foregroundStyle(.white)
            Text(message)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                ChromaticButton(title: actionTitle, systemImage: "sparkles", action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

/// Primary apply control: one click applies everywhere; the chevron picks a single display.
struct ApplyControl: View {
    let wallpaper: Wallpaper
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ChromaticButton(
                title: model.isPlaying(wallpaper) ? "On Your Desktop" : "Set as Wallpaper",
                systemImage: model.isPlaying(wallpaper) ? "checkmark" : "play.fill",
                progress: model.downloads[wallpaper.id]
            ) {
                model.apply(wallpaper)
            }
            if model.displays.count > 1 {
                Menu {
                    Button("All Displays") { model.apply(wallpaper) }
                    Divider()
                    ForEach(model.displays) { display in
                        Button(display.name) { model.apply(wallpaper, to: .display(display.key)) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .glassCircle(interactive: true)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a display")
                .accessibilityLabel("Choose a display")
            }
        }
    }
}
