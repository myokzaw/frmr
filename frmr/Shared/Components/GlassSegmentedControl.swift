import SwiftUI

// v5.1 F10: the Library's Roll / Entries / Strips switch, a glass capsule
// with a soft accent fill under the selected segment. Not a Picker so the
// segments keep their own accessibility identifiers.
struct GlassSegmentedControl<Value: Hashable>: View {
    struct Segment {
        let value: Value
        let title: String
        let identifier: String
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let segments: [Segment]
    let selection: Value
    let accent: Color
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.title) { segment in
                SegmentButton(
                    title: segment.title,
                    identifier: segment.identifier,
                    isSelected: segment.value == selection,
                    accent: accent,
                    action: { onSelect(segment.value) }
                )
            }
        }
        .padding(Constants.LibraryUI.segmentPadding)
        .frmrAdaptiveGlassCapsule()
        .animation(reduceMotion ? nil : .easeInOut(duration: Constants.LibraryUI.segmentedAnimationDuration), value: selection)
    }
}

private struct SegmentButton: View {
    let title: String
    let identifier: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? accent : .secondary)
                .frame(maxWidth: .infinity, minHeight: Constants.LibraryUI.segmentHeight)
                .background(isSelected ? accent.opacity(Constants.LibraryUI.segmentSelectedOpacity) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
