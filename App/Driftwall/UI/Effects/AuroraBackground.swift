import SwiftUI

/// Soft aurora behind the whole app: a slowly drifting mesh of deep violet, teal and rose over the
/// ink base, with a vignette so content stays the focus. Freezes for Reduce Motion.
struct AuroraBackground: View {
    var opacity: Double = 1
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive
    @State private var start = Date()

    private static let frameInterval = 1.0 / 20.0
    private static let drift = 0.07

    /// Each hue is mixed into the ink so the mesh stays dark and never competes with artwork.
    private static let colors: [Color] = [
        tinted(Theme.violet, 0.34), Theme.ink, tinted(Theme.teal, 0.16),
        tinted(Theme.teal, 0.12), tinted(Theme.violet, 0.20), tinted(Theme.rose, 0.18),
        tinted(Theme.teal, 0.14), Theme.ink, tinted(Theme.violet, 0.30),
    ]

    private static func tinted(_ color: Color, _ amount: Double) -> Color {
        Theme.ink.mix(with: color, by: amount)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: reduceMotion || !isActive || !animationsActive)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(start)
            MeshGradient(width: 3, height: 3, points: Self.points(at: time), colors: Self.colors, smoothsColors: true)
        }
        .overlay {
            RadialGradient(colors: [.clear, Theme.ink.opacity(0.55)], center: .center, startRadius: 240, endRadius: 900)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Corners stay pinned; the edge midpoints and centre wander on slow, unrelated cycles.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wobble(_ speed: Double, _ phase: Double) -> Float { Float(sin(time * speed + phase) * drift) }
        return [
            [0, 0], [0.5 + wobble(0.11, 0), 0], [1, 0],
            [0, 0.5 + wobble(0.13, 1.7)], [0.5 + wobble(0.09, 3.1), 0.5 + wobble(0.12, 4.4)], [1, 0.5 + wobble(0.10, 2.3)],
            [0, 1], [0.5 + wobble(0.14, 5.2), 1], [1, 1],
        ]
    }
}
