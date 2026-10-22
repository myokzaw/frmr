import SwiftUI

/// One tool in a `ToolIconBar`.
struct ToolIconItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let hint: String
}

// v5.1 F8/F10: the row of tool icons under a photo or strip (Film, Print,
// Halation …). Selecting one swaps the scrubber or chips above it. A small
// dot marks a tool whose value differs from the stock default. Pure
// presentation: the selection lives with the caller.
struct ToolIconBar: View {
    let items: [ToolIconItem]
    let selectedID: String
    let modifiedIDs: Set<String>
    let identifierPrefix: String
    let selectedColor: Color
    let idleColor: Color
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    ToolIconButton(
                        item: item,
                        isSelected: item.id == selectedID,
                        isModified: modifiedIDs.contains(item.id),
                        identifier: "\(identifierPrefix).\(item.id)",
                        selectedColor: selectedColor,
                        idleColor: idleColor,
                        action: { onSelect(item.id) }
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ToolIconButton: View {
    let item: ToolIconItem
    let isSelected: Bool
    let isModified: Bool
    let identifier: String
    let selectedColor: Color
    let idleColor: Color
    let action: () -> Void

    private var color: Color {
        isSelected ? selectedColor : idleColor.opacity(Constants.ScrubberUI.toolIdleOpacity)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Constants.CameraUI.filmChipLineSpacing * 2) {
                Image(systemName: item.systemImage)
                    .font(.system(size: Constants.ScrubberUI.toolIconSize, weight: .regular))
                    .frame(height: Constants.ScrubberUI.toolIconSize + Constants.CameraUI.chipSpacing)
                Text(item.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(Constants.ScrubberUI.toolTitleMinScale)
                Circle()
                    .fill(isModified ? selectedColor : .clear)
                    .frame(width: Constants.ScrubberUI.toolDotSize, height: Constants.ScrubberUI.toolDotSize)
            }
            .foregroundStyle(color)
            .frame(width: Constants.ScrubberUI.toolItemWidth, height: Constants.ScrubberUI.toolItemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(isModified ? "Changed" : "")
        .accessibilityHint(item.hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
