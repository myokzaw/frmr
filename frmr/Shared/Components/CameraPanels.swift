import SwiftUI

// v5.1 F8 camera panels: white balance and exposure open as glass sheets
// from the two small buttons at the top right. A sheet is a wide card, so it
// stays upright; only its round preset and step buttons turn their glyphs.

private struct PanelHeader: View {
    let title: String
    let valueText: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(valueText)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.appAmber)
                .accessibilityHidden(true)
        }
    }
}

private struct PanelSliderRow: View {
    let title: String
    // The EV row has no room for a label: the header above says what it is
    let showsTitle: Bool
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let identifier: String

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            if showsTitle {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .frame(width: Constants.CameraUI.panelSliderLabelWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
            Slider(value: $value, in: range, step: step)
                .tint(.appAmber)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
                .accessibilityIdentifier(identifier)
            if showsTitle {
                Text(valueText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .frame(width: Constants.CameraUI.panelValueWidth, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct WhiteBalancePanel: View {
    let activePreset: WBMode?
    let kelvin: Float
    let tint: Float
    let valueText: String
    let onPreset: (WBMode) -> Void
    let onKelvin: (Float) -> Void
    let onTint: (Float) -> Void

    /// "5600K"
    nonisolated static func kelvinText(_ kelvin: Float) -> String {
        "\(Int(kelvin.rounded()))K"
    }

    /// "+12", "-8", "0"
    nonisolated static func tintText(_ tint: Float) -> String {
        let value = Int(tint.rounded())
        return value == 0 ? "0" : String(format: "%+d", value)
    }

    var body: some View {
        VStack(spacing: Constants.CameraUI.panelSpacing) {
            PanelHeader(title: "White balance", valueText: valueText)
            HStack(spacing: Constants.CameraUI.chipSpacing) {
                ForEach(WBMode.allCases) { mode in
                    CameraChip(
                        systemImage: mode.symbolName,
                        accessibilityLabel: "White balance: \(mode.label)",
                        isSelected: mode == activePreset,
                        action: { onPreset(mode) }
                    )
                    .accessibilityIdentifier("camera.wb.\(mode.rawValue)")
                }
            }
            PanelSliderRow(
                title: "Kelvin",
                showsTitle: true,
                valueText: Self.kelvinText(kelvin),
                value: Binding(get: { Double(kelvin) }, set: { onKelvin(Float($0)) }),
                range: Double(Constants.Camera.whiteBalanceKelvinRange.lowerBound)...Double(Constants.Camera.whiteBalanceKelvinRange.upperBound),
                step: Constants.CameraUI.kelvinSliderStep,
                identifier: "camera.wb.kelvin"
            )
            PanelSliderRow(
                title: "Tint",
                showsTitle: true,
                valueText: Self.tintText(tint),
                value: Binding(get: { Double(tint) }, set: { onTint(Float($0)) }),
                range: Double(Constants.Camera.whiteBalanceTintRange.lowerBound)...Double(Constants.Camera.whiteBalanceTintRange.upperBound),
                step: Constants.CameraUI.tintSliderStep,
                identifier: "camera.wb.tint"
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.wb.panel")
    }
}

struct ExposurePanel: View {
    let bias: Float
    let readout: String
    let onBias: (Float) -> Void
    let onStep: (Int) -> Void

    var body: some View {
        VStack(spacing: Constants.CameraUI.panelSpacing) {
            PanelHeader(title: "Exposure", valueText: readout)
            HStack(spacing: Constants.CameraUI.chipSpacing) {
                CameraChip(
                    systemImage: "minus",
                    accessibilityLabel: "Darker",
                    isSelected: false,
                    action: { onStep(-1) }
                )
                .accessibilityIdentifier("camera.ev.darker")
                PanelSliderRow(
                    title: "Exposure",
                    showsTitle: false,
                    valueText: readout,
                    value: Binding(get: { Double(bias) }, set: { onBias(Float($0)) }),
                    range: Double(Constants.Camera.exposureBiasMin)...Double(Constants.Camera.exposureBiasMax),
                    step: Double(Constants.Camera.exposureStep),
                    identifier: "camera.ev.slider"
                )
                CameraChip(
                    systemImage: "plus",
                    accessibilityLabel: "Brighter",
                    isSelected: false,
                    action: { onStep(1) }
                )
                .accessibilityIdentifier("camera.ev.brighter")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.ev.panel")
    }
}
