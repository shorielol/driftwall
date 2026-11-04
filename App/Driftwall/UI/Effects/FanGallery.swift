import DriftwallCore
import SwiftUI

/// Posters fanned like a hand of cards; hovering spreads them, clicking selects.
struct FanGallery: View {
    let wallpapers: [Wallpaper]
    let selectedID: String?
    let onSelect: (Wallpaper) -> Void

    @State private var isSpread = false
    @State private var hoveredID: String?

    private let cardSize = CGSize(width: 168, height: 95)

    var body: some View {
        let count = wallpapers.count
        ZStack {
            ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                let centered = Double(index) - Double(count - 1) / 2
                let spread = isSpread ? 1.0 : 0.7
                WallpaperPoster(wallpaper: wallpaper)
                    .frame(width: cardSize.width, height: cardSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(wallpaper.id == selectedID ? Color.white : Color.white.opacity(0.25), lineWidth: wallpaper.id == selectedID ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                    .scaleEffect(hoveredID == wallpaper.id ? 1.08 : 1)
                    .rotationEffect(.degrees(centered * 7 * spread), anchor: .bottom)
                    .offset(x: centered * 62 * spread, y: abs(centered) * 7 * spread - (hoveredID == wallpaper.id ? 14 : 0))
                    .zIndex(hoveredID == wallpaper.id ? 100 : Double(index))
                    .onHover { hovering in
                        withAnimation(Theme.Motion.lively) { hoveredID = hovering ? wallpaper.id : nil }
                    }
                    .onTapGesture { onSelect(wallpaper) }
                    .accessibilityElement()
                    .accessibilityLabel(Text(wallpaper.title))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { onSelect(wallpaper) }
            }
        }
        .frame(width: cardSize.width + 62 * Double(max(0, count - 1)) + 40, height: cardSize.height + 50)
        .onHover { hovering in
            withAnimation(Theme.Motion.lively) { isSpread = hovering }
        }
    }
}
