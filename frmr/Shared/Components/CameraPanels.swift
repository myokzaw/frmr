import SwiftUI

// v5 F3 Photo-mode controls: the WB and EV chips and the compact panel each
// opens. Chips are the usual fixed 44pt discs whose glyph turns in place; a
// panel is a wide card, so it stays upright and only its round preset and
// step buttons turn their glyphs (wide views don't rotate).

// A symbol over a short value, sized like the Film chip's glyph
struct ChipValueGlyph: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: Constants.CameraUI.filmChipLineSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: Constants.CameraUI.filmChipSymbolSize, weight: .medium))
            Text(text)
                .font(.system(size: Constants.CameraUI.filmChipCodeFontSize, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(Constants.CameraUI.filmChipCodeMinScale)
        }
        .frame(width: Constants.CameraUI.filmChipContentWidth)
    }
}

// The two chips above the dial. Selected = its panel is open.
struct PhotoControlChips: View {
    let whiteBalanceText: String
    let exposureText: String
    let isWhiteBalanceOpen: Bool
    let isExposureOpen: Bool
    let onToggleWhiteBalance: () -> Void
    let onToggleExposure: () -> Void

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            CameraChip(
                isSelected: isWhiteBalanceOpen,
                accessibilityLabel: "White balance",
                action: onToggleWhiteBalance
            ) {
                ChipValueGlyph(systemImage: "thermometer.medium", text: whiteBalanceText)
            }
            .accessibilityValue(whiteBalanceText)
            .accessibilityHint(isWhiteBalanceOpen ? "Closes the white balance controls" : "Opens the white balance controls")
            .accessibilityIdentifier("camera.wb.chip")

            CameraChip(
                isSelected: isExposureOpen,
                accessibilityLabel: "Exposure compensation",
                action: onToggleExposure
            ) {
                ChipValueGlyph(systemImage: "plusminus", text: exposureText)
            }
            .accessibilityValue(exposureText)
            .accessibilityHint(isExposureOpen ? "Closes the exposure controls" : "Opens the exposure controls")
            .accessibilityIdentifier("camera.ev.chip")
        }
    }
}

private struct PanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: Constants.CameraUI.panelSpacing) {
            content
        }
        .foregroundStyle(.white)
        .padding(Constants.CameraUI.panelPadding)
        .frame(maxWidth: Constants.CameraUI.panelMaxWidth)
        .background(.black.opacity(Constants.CameraUI.panelBackgroundOpacity), in: RoundedRectangle(cornerRadius: Constants.CameraUI.panelCornerRadius))
        .padding(.horizontal, Constants.CameraUI.panelHorizontalMargin)
    }
}

private struct PanelSliderRow: View {
    let title: String
    // The EV row has no room for a label: the chip beside it says what it is
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
            Text(valueText)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: Constants.CameraUI.panelValueWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

struct WhiteBalancePanel: View {
    let activePreset: WBMode?
    let kelvin: Float
    let tint: Float
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
        PanelCard {
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
        PanelCard {
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
