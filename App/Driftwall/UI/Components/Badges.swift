import DriftwallCore
import SwiftUI

struct Badge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.4)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
    }
}

struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(Theme.auroraGradient, in: Capsule())
            .accessibilityLabel("New in this drop")
    }
}

/// Animated equaliser bars marking what is on the desktop right now.
struct NowPlayingIndicator: View {
    var isPaused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: isPaused || reduceMotion || !animationsActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(Theme.teal)
                        .frame(width: 3, height: isPaused ? 4 : 4 + 7 * abs(sin(t * 3 + Double(index) * 1.3)))
                }
            }
            .frame(height: 11, alignment: .bottom)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .accessibilityLabel(isPaused ? "On your desktop, paused" : "On your desktop")
    }
}

struct WallpaperMeta: View {
    let wallpaper: Wallpaper

    var body: some View {
        HStack(spacing: 6) {
            if wallpaper.isOriginal {
                Text("LIVE").fontWeight(.bold).foregroundStyle(Theme.teal)
                Text("·")
                Text(wallpaper.originalScene?.medium ?? "Original")
                Text("·")
                Text("Any resolution")
            } else {
                Text(wallpaper.resolutionLabel).fontWeight(.bold).foregroundStyle(wallpaper.is4K ? Theme.teal : Theme.amber)
                Text("·")
                Text(wallpaper.category)
                Text("·")
                Text(wallpaper.durationLabel).monospacedDigit()
            }
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(Theme.textSecondary)
    }
}
