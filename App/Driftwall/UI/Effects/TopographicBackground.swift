import SwiftUI

/// Animated contour-line field behind the whole app. Freezes for Reduce Motion.
struct TopographicBackground: View {
    var tintA: Color = Theme.teal
    var tintB: Color = Theme.violet
    var density: Float = 9
    var opacity: Double = 0.55
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isActive || !animationsActive)) { timeline in
            let time = Float(timeline.date.timeIntervalSince(start))
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.black)
                    .colorEffect(
                        ShaderLibrary.topographicFlow(
                            .float2(proxy.size),
                            .float(reduceMotion ? 0 : time),
                            .color(tintA),
                            .color(tintB),
                            .float(density)
                        )
                    )
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
