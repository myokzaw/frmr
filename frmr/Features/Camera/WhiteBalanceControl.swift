import SwiftUI

nonisolated enum WBMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case sunlight
    case cloudy
    case shade
    case tungsten
    case fluorescent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .sunlight: return "Daylight"
        case .cloudy: return "Cloudy"
        case .shade: return "Shade"
        case .tungsten: return "Tungsten"
        case .fluorescent: return "Fluorescent"
        }
    }

    // nil means continuous auto white balance
    var temperatureAndTint: (temperature: Float, tint: Float)? {
        switch self {
        case .auto: return nil
        case .sunlight: return Constants.WhiteBalance.sunlight
        case .cloudy: return Constants.WhiteBalance.cloudy
        case .shade: return Constants.WhiteBalance.shade
        case .tungsten: return Constants.WhiteBalance.tungsten
        case .fluorescent: return Constants.WhiteBalance.fluorescent
        }
    }

    // SF Symbol per mode. Icons, not text: "Fluorescent" in a rotating chip
    // would be wider than any fixed frame can hold when turned on its side.
    var symbolName: String {
        switch self {
        case .auto: return "a.circle"
        case .sunlight: return "sun.max"
        case .cloudy: return "cloud"
        case .shade: return "cloud.sun"
        case .tungsten: return "lightbulb"
        case .fluorescent: return "light.panel"
        }
    }
}

// Collapsed (the resting state, v3 F3) this is a single chip showing the
// active mode's glyph; tapping it expands the full bank inline. Selecting any
// mode — or tapping the viewfinder — collapses it again. Every chip is the
// same fixed circle, so the control never reflows when the phone turns; only
// the glyphs rotate (see CameraChip).
struct WhiteBalanceControl: View {
    let selected: WBMode
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (WBMode) -> Void

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            ForEach(CameraViewModel.visibleModes(expanded: isExpanded, selected: selected)) { mode in
                CameraChip(
                    systemImage: mode.symbolName,
                    accessibilityLabel: "White balance: \(mode.label)",
                    isSelected: mode == selected,
                    action: { isExpanded ? onSelect(mode) : onToggle() }
                )
            }
        }
        .animation(
            .easeInOut(duration: Constants.CameraUI.wbExpandAnimationDuration),
            value: isExpanded
        )
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 40) {
            WhiteBalanceControl(selected: .auto, isExpanded: false, onToggle: {}, onSelect: { _ in })
            WhiteBalanceControl(selected: .auto, isExpanded: true, onToggle: {}, onSelect: { _ in })
        }
    }
}
