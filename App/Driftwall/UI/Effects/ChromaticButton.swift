import SwiftUI

/// Primary call to action: dark glass capsule with a prismatic rim that spins while hovered or busy,
/// and fills as a progress bar during downloads.
struct ChromaticButton: View {
    let title: String
    var systemImage: String?
    var progress: Double?
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsActive) private var animationsActive

    private var isBusy: Bool { progress != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let progress {
                    ProgressRing(progress: progress)
                        .frame(width: 15, height: 15)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(progressLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(fill)
            .overlay(rim)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(Theme.Motion.standard) { isHovering = hovering }
        }
        .accessibilityLabel(Text(progressLabel))
    }

    private var progressLabel: String {
        guard let progress else { return title }
        return "Downloading \(Int((progress * 100).rounded()))%"
    }

    private var fill: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule()
                    .fill(Theme.auroraGradient.opacity(isBusy ? 0.55 : (isHovering ? 0.38 : 0.26)))
                    .frame(width: isBusy ? max(proxy.size.height, proxy.size.width * (progress ?? 0)) : proxy.size.width)
            }
        }
        .clipShape(Capsule())
    }

    private var rim: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !animationsActive || !(isHovering || isBusy))) { timeline in
            let degrees = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90
            let gradient = AngularGradient(colors: Theme.aurora, center: .center, angle: .degrees(degrees))
            ZStack {
                Capsule().strokeBorder(gradient, lineWidth: 1.5)
                Capsule().strokeBorder(gradient, lineWidth: 6).blur(radius: 10).opacity(isHovering || isBusy ? 0.75 : 0.35)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Instant press feedback on mouse-down, critically damped release.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? Theme.Motion.press : Theme.Motion.lively, value: configuration.isPressed)
    }
}

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.Motion.standard, value: progress)
    }
}

/// Secondary glass action.
struct GlassButton: View {
    let title: String?
    let systemImage: String
    var isOn = false
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.bounce, value: isOn)
                if let title {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(isOn ? Theme.rose : .white)
            .padding(.horizontal, title == nil ? 0 : 16)
            .frame(minWidth: 42, minHeight: 42)
            .glassCapsule(interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .help(help ?? title ?? "")
        .accessibilityLabel(Text(help ?? title ?? systemImage))
    }
}
