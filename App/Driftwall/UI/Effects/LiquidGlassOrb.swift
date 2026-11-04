import SwiftUI

/// A glowing glass sphere with drifting aurora blobs inside. Used for loading, empty states and the drop countdown.
struct LiquidGlassOrb: View {
    var size: CGFloat = 120
    var isAnimating = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isAnimating || !animationsActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize)
                let circle = Path(ellipseIn: rect)
                context.clip(to: circle)
                context.fill(circle, with: .color(Theme.ink))

                var blobs = context
                blobs.addFilter(.blur(radius: canvasSize.width * 0.16))
                let blobColors = [Theme.teal, Theme.violet, Theme.rose]
                for (index, color) in blobColors.enumerated() {
                    let phase = Double(index) * 2.1
                    let x = canvasSize.width * (0.5 + 0.28 * cos(t * 0.45 + phase))
                    let y = canvasSize.height * (0.5 + 0.28 * sin(t * 0.37 + phase * 1.3))
                    let radius = canvasSize.width * 0.36
                    blobs.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                }

                let highlight = Gradient(colors: [.white.opacity(0.55), .white.opacity(0)])
                let spot = CGRect(x: rect.width * 0.18, y: rect.height * 0.08, width: rect.width * 0.5, height: rect.height * 0.32)
                context.fill(
                    Path(ellipseIn: spot),
                    with: .linearGradient(highlight, startPoint: CGPoint(x: spot.midX, y: spot.minY), endPoint: CGPoint(x: spot.midX, y: spot.maxY))
                )
                context.stroke(circle, with: .color(.white.opacity(0.28)), lineWidth: 1.2)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.violet.opacity(0.45), radius: size * 0.25)
        .accessibilityHidden(true)
    }
}
