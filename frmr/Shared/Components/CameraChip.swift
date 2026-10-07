import SwiftUI

// Round chip over the viewfinder — shared by the WB bank and the lens
// selector. Always a fixed square frame so it can turn about its own centre
// in landscape without swinging into its neighbours: a text pill wider than
// tall would overflow vertically when rotated and nothing would reflow to
// make room. The disc stays put; only the glyph inside rotates.
struct CameraChip<Glyph: View>: View {
    let isSelected: Bool
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    private var background: Color {
        isSelected ? .appTealDark : .white.opacity(Constants.CameraUI.chipInactiveOpacity)
    }

    var body: some View {
        Button(action: action) {
            glyph()
                .foregroundStyle(.white)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.chipDiameter, height: Constants.CameraUI.chipDiameter)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension CameraChip where Glyph == Text {
    init(label: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, accessibilityLabel: label, action: action) {
            Text(label)
                .font(.system(size: Constants.CameraUI.chipFontSize, weight: isSelected ? .semibold : .medium))
        }
    }
}

extension CameraChip where Glyph == ChipSymbol {
    init(systemImage: String, accessibilityLabel: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(isSelected: isSelected, accessibilityLabel: accessibilityLabel, action: action) {
            ChipSymbol(systemImage: systemImage)
        }
    }
}

struct ChipSymbol: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Constants.CameraUI.chipIconSize, weight: .medium))
    }
}

#Preview {
    ZStack {
        Color.black
        HStack {
            CameraChip(label: "0.5×", isSelected: true, action: {})
            CameraChip(systemImage: "sun.max", accessibilityLabel: "Daylight", isSelected: false, action: {})
        }
    }
}
