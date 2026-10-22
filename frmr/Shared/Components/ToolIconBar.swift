import SwiftUI

/// One tool in a `ToolIconBar`.
struct ToolIconItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let hint: String
    /// What VoiceOver reads after the title ("120%", "+0.3 EV"); empty for none.
    var value: String = ""
    /// 0…1 arc drawn around the glyph (the tool's current value); nil draws none.
    var ring: Double?
}

/// The value ring's arithmetic (research §4.6), kept out of the view so it
/// is unit-testable.
nonisolated enum ToolRing {
    /// An effect strength (0…1.5) as a share of the full ring.
    static func fraction(strength: Double, range: ClosedRange<Double> = FilmLook.strengthRange) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((strength - range.lowerBound) / span, 0), 1)
    }

    /// Exposure: no ring at 0 EV, otherwise how far it is from 0 as a share
    /// of the widest setting either way.
    static func fraction(exposure: Double, range: ClosedRange<Double> = FilmLook.exposureRange) -> Double? {
        let limit = max(abs(range.lowerBound), abs(range.upperBound))
        guard exposure != 0, limit > 0 else { return nil }
        return min(abs(exposure) / limit, 1)
    }
}

// v5.1 F8/F10, v5.2 M5: the row of tool icons under a photo or strip
// (Exposure, Film, Print, Halation …). Selecting one swaps the scrubber or
// previews above it. Each effect wears a value ring (Photos-app style) in
// place of the v5.1 "modified" dot; the ring is decorative and the value is
// in VoiceOver. Pure presentation: the selection lives with the caller.
struct ToolIconBar: View {
    let items: [ToolIconItem]
    let selectedID: String
    let identifierPrefix: String
    /// The selected tool and the rings. Amber on darkroom; the theme tint on
    /// paper (amber is never a thin line on cream).
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
        .sensoryFeedback(.selection, trigger: selectedID)
    }
}

private struct ToolIconButton: View {
    let item: ToolIconItem
    let isSelected: Bool
    let identifier: String
    let selectedColor: Color
    let idleColor: Color
    let action: () -> Void

    private typealias UI = Constants.ScrubberUI

    private var color: Color {
        isSelected ? selectedColor : idleColor.opacity(UI.toolIdleOpacity)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Constants.DesignUI.Space.xs) {
                Image(systemName: item.systemImage)
                    .font(.system(size: UI.toolIconSize, weight: .medium))
                    .frame(width: UI.toolRingDiameter, height: UI.toolRingDiameter)
                    .overlay { ValueRing(fraction: item.ring, color: selectedColor, trackColor: idleColor) }
                Text(item.title)
                    .font(.frmrMeta.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(color)
            .padding(.horizontal, Constants.DesignUI.Space.xs)
            .frame(minWidth: UI.toolItemWidth, minHeight: UI.toolItemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.value)
        .accessibilityHint(item.hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The thin arc around a tool's glyph: a faint full track and the value on top.
private struct ValueRing: View {
    let fraction: Double?
    let color: Color
    let trackColor: Color

    private typealias UI = Constants.ScrubberUI

    var body: some View {
        if let fraction {
            ZStack {
                Circle()
                    .stroke(trackColor.opacity(UI.toolRingTrackOpacity), lineWidth: UI.toolRingWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: UI.toolRingWidth, lineCap: .round))
                    .rotationEffect(.degrees(UI.toolRingStartDegrees))
            }
            .frmrAnimation(.snap, value: fraction)
            .accessibilityHidden(true)
        }
    }
}
