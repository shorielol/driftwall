import SwiftUI

/// Brand-consistent segmented control (the system one picks up the user's accent colour).
struct GlassSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(Theme.Motion.standard) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .glassCapsule()
        .fixedSize()
    }
}

/// Tracks whether the window can actually be seen, so animations and video stop when it can't.
struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ProbeView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            guard let window else { return }
            let center = NotificationCenter.default
            let names: [(Notification.Name, AnyObject?)] = [
                (NSWindow.didChangeOcclusionStateNotification, window),
                (NSWindow.didMiniaturizeNotification, window),
                (NSWindow.didDeminiaturizeNotification, window),
                (NSApplication.didHideNotification, nil),
                (NSApplication.didUnhideNotification, nil),
            ]
            for (name, object) in names {
                tokens.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        private func report() {
            guard let window else { return }
            onChange?(window.occlusionState.contains(.visible) && !window.isMiniaturized && !NSApp.isHidden)
        }
    }
}

extension EnvironmentValues {
    /// False while the window is hidden, minimised or fully covered.
    @Entry var animationsActive: Bool = true
}
