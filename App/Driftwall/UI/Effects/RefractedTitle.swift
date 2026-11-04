import SwiftUI

/// Display title with a soft chromatic split, like light refracting through glass.
/// The split widens on hover and collapses for Reduce Motion.
struct RefractedTitle: View {
    let text: String
    var size: CGFloat = 56
    var isHighlighted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var split: CGFloat {
        guard !reduceMotion else { return 0 }
        return isHighlighted ? size * 0.045 : size * 0.018
    }

    var body: some View {
        ZStack {
            layer.foregroundStyle(Theme.teal.opacity(0.85)).offset(x: -split, y: 0)
            layer.foregroundStyle(Theme.rose.opacity(0.85)).offset(x: split, y: split * 0.3)
            layer.foregroundStyle(.white)
        }
        .compositingGroup()
        .animation(Theme.Motion.standard, value: split)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(.isHeader)
    }

    private var layer: some View {
        Text(text)
            .font(Theme.Typeface.display(size))
            .displayTracking(size)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .blendMode(.plusLighter)
    }
}
