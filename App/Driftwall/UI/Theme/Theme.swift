import SwiftUI

/// Design tokens. Dark, cinematic, aurora accents.
enum Theme {
    static let ink = Color(red: 0.035, green: 0.035, blue: 0.07)
    static let inkRaised = Color(red: 0.07, green: 0.07, blue: 0.12)
    static let hairline = Color.white.opacity(0.10)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary = Color.white.opacity(0.45)

    static let teal = Color(red: 0.20, green: 0.95, blue: 0.85)
    static let violet = Color(red: 0.56, green: 0.42, blue: 1.00)
    static let rose = Color(red: 1.00, green: 0.38, blue: 0.70)
    static let amber = Color(red: 1.00, green: 0.78, blue: 0.35)

    static let aurora: [Color] = [teal, violet, rose, teal]
    static let auroraGradient = LinearGradient(colors: [teal, violet, rose], startPoint: .leading, endPoint: .trailing)

    enum Space {
        static let gutter: CGFloat = 40
        static let section: CGFloat = 28
        static let card: CGFloat = 14
    }

    enum Radius {
        static let card: CGFloat = 14
        static let panel: CGFloat = 22
        static let hero: CGFloat = 28
    }

    enum Motion {
        /// Critically damped default (no overshoot).
        static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
        /// Slight overshoot, for hover lift and press release only.
        static let lively = Animation.spring(response: 0.32, dampingFraction: 0.82)
        static let press = Animation.spring(response: 0.18, dampingFraction: 1.0)
        static let fade = Animation.easeOut(duration: 0.22)
    }

    enum Typeface {
        static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
        static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
        static let body = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 11, weight: .medium)
        static let eyebrow = Font.system(size: 11, weight: .bold).width(.expanded)
    }
}

extension View {
    /// Large display text wants negative tracking.
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(size >= 28 ? -size * 0.022 : 0)
    }
}
