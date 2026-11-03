import SwiftUI

// F-122-H camera controls: Exposure, Zoom and White balance take the stock
// dial's place above the shutter row (the iOS Camera pattern), so the shutter
// stays usable while one is open. Each is a wide glass card, so it stays
// upright in landscape; only its round chips turn their glyphs.

/// The shared frame: glass behind, one container with the control's name
/// and identifier (the visible title is gone, so VoiceOver gets it here;
/// focus lands on it when it appears).
private struct DialSlotCard<Content: View>: View {
    let label: String
    let identifier: String
    @ViewBuilder let content: () -> Content

    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        content()
            .foregroundStyle(.white)
            .frmrChromeTypeSize()
            .padding(.horizontal, Constants.CameraUI.controlPanelPadding)
            .padding(.vertical, Constants.CameraUI.panelVerticalPadding)
            .frmrGlass(in: RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.sheet))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .accessibilityFocused($isFocused)
            .onAppear { isFocused = true }
    }
}

private struct PanelCloseChip: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        CameraChip(systemImage: "xmark", accessibilityLabel: "Close", isSelected: false, action: action)
            .accessibilityIdentifier("\(identifier).close")
    }
}

/// The readout at the leading edge: a fixed width with monospaced digits, so
/// the ruler beside it never shifts as the text changes.
private struct PanelReadout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline.monospacedDigit().weight(.semibold))
            .foregroundStyle(Color.appAmber)
            .lineLimit(1)
            .minimumScaleFactor(Constants.CameraUI.panelReadoutMinScale)
            .frame(width: Constants.CameraUI.panelReadoutWidth, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// One clean row for Exposure and Zoom: readout, ruler (which takes all the
/// width left), then the x. Exposure also has - / + beside the ruler.
private struct RulerPanel: View {
    let label: String
    let readout: String
    let identifier: String
    var steps: Steps?
    let onClose: () -> Void
    let ruler: EffectScrubber

    struct Steps {
        let minusLabel: String
        let plusLabel: String
        let minusIdentifier: String
        let plusIdentifier: String
        let onStep: (Int) -> Void
    }

    var body: some View {
        DialSlotCard(label: label, identifier: identifier) {
            HStack(spacing: Constants.CameraUI.panelRowSpacing) {
                PanelReadout(text: readout)
                if let steps {
                    CameraChip(
                        systemImage: "minus", accessibilityLabel: steps.minusLabel, isSelected: false,
                        action: { steps.onStep(-1) }
                    )
                    .accessibilityIdentifier(steps.minusIdentifier)
                }
                ruler
                if let steps {
                    CameraChip(
                        systemImage: "plus", accessibilityLabel: steps.plusLabel, isSelected: false,
                        action: { steps.onStep(1) }
                    )
                    .accessibilityIdentifier(steps.plusIdentifier)
                }
                PanelCloseChip(identifier: identifier, action: onClose)
            }
            .frame(height: Constants.CameraUI.panelRowHeight)
        }
    }
}

struct ExposurePanel: View {
    let bias: Float
    let readout: String
    let onBias: (Float) -> Void
    let onStep: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        RulerPanel(
            label: "Exposure",
            readout: readout,
            identifier: "camera.ev.panel",
            steps: .init(
                minusLabel: "Darker",
                plusLabel: "Brighter",
                minusIdentifier: "camera.ev.darker",
                plusIdentifier: "camera.ev.brighter",
                onStep: onStep
            ),
            onClose: onClose,
            ruler: EffectScrubber(
                title: "Exposure",
                value: Binding(get: { Double(bias) }, set: { onBias(Float($0)) }),
                defaultValue: 0,
                hint: "Adjusts exposure in thirds of a stop",
                identifier: "camera.ev.slider",
                textColor: .white,
                tint: .appAmber,
                scale: .cameraExposure,
                valueText: readout,
                resetHint: "Returns to 0 EV",
                showsHeader: false
            )
        )
    }
}

/// The Zoom control (F-122-G): the Exposure row without - / +, over the zoom
/// ruler, 1...3x in 0.2 steps. `onLiveZoom` carries the unsnapped position
/// while the ruler is dragged, so the viewfinder moves smoothly.
struct ZoomPanel: View {
    let zoom: CGFloat
    let readout: String
    let onZoom: (CGFloat) -> Void
    let onLiveZoom: (Double?) -> Void
    let onClose: () -> Void

    var body: some View {
        RulerPanel(
            label: "Zoom",
            readout: readout,
            identifier: "camera.zoom.panel",
            onClose: onClose,
            ruler: EffectScrubber(
                title: "Zoom",
                value: Binding(get: { Double(zoom) }, set: { onZoom(CGFloat($0)) }),
                defaultValue: Double(Constants.Camera.minZoomFactor),
                hint: "Adjusts zoom in steps of two tenths",
                identifier: "camera.zoom.slider",
                textColor: .white,
                tint: .appAmber,
                scale: .cameraZoom,
                valueText: readout,
                resetHint: "Returns to 1 times",
                showsHeader: false,
                onLiveValue: onLiveZoom
            )
        )
    }
}

/// White balance: presets in a scrolling row, then one slider whose value is
/// chosen by the Kelvin | Tint switch.
struct WhiteBalancePanel: View {
    let activePreset: WBMode?
    let axis: CameraViewModel.WhiteBalanceAxis
    let kelvin: Float
    let tint: Float
    let kelvinText: String
    let tintText: String
    let onPreset: (WBMode) -> Void
    let onAxis: (CameraViewModel.WhiteBalanceAxis) -> Void
    let onKelvin: (Float) -> Void
    let onTint: (Float) -> Void
    let onClose: () -> Void

    // The x sits top-trailing, level with the presets, so the second row's
    // slider keeps the full width.
    var body: some View {
        DialSlotCard(label: "White balance", identifier: "camera.wb.panel") {
            VStack(spacing: Constants.CameraUI.panelSpacing) {
                HStack(spacing: Constants.CameraUI.panelRowSpacing) {
                    presets
                    PanelCloseChip(identifier: "camera.wb.panel", action: onClose)
                }
                .frame(height: Constants.CameraUI.panelRowHeight)
                HStack(spacing: Constants.CameraUI.panelRowSpacing) {
                    Picker("Value", selection: Binding(get: { axis }, set: onAxis)) {
                        ForEach(CameraViewModel.WhiteBalanceAxis.allCases) { axis in
                            Text(axis.label).tag(axis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: Constants.CameraUI.panelAxisSwitchWidth)
                    .accessibilityIdentifier("camera.wb.axis")
                    slider
                    Text(axis == .kelvin ? kelvinText : tintText)
                        .font(.frmrValue)
                        .foregroundStyle(Color.appAmber)
                        .lineLimit(1)
                        .minimumScaleFactor(Constants.CameraUI.valueButtonMinScale)
                        .frame(width: Constants.CameraUI.panelValueWidth, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                .frame(height: Constants.CameraUI.panelSecondRowHeight)
            }
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.CameraUI.panelPresetSpacing) {
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
        }
    }

    // One slider, so the identifier follows the value it edits
    @ViewBuilder private var slider: some View {
        switch axis {
        case .kelvin:
            Slider(
                value: Binding(get: { Double(kelvin) }, set: { onKelvin(Float($0)) }),
                in: Double(Constants.Camera.whiteBalanceKelvinRange.lowerBound)...Double(Constants.Camera.whiteBalanceKelvinRange.upperBound),
                step: Constants.CameraUI.kelvinSliderStep
            )
            .tint(.appAmber)
            .accessibilityLabel("Kelvin")
            .accessibilityValue(kelvinText)
            .accessibilityIdentifier("camera.wb.kelvin")
        case .tint:
            Slider(
                value: Binding(get: { Double(tint) }, set: { onTint(Float($0)) }),
                in: Double(Constants.Camera.whiteBalanceTintRange.lowerBound)...Double(Constants.Camera.whiteBalanceTintRange.upperBound),
                step: Constants.CameraUI.tintSliderStep
            )
            .tint(.appAmber)
            .accessibilityLabel("Tint")
            .accessibilityValue(tintText)
            .accessibilityIdentifier("camera.wb.tint")
        }
    }
}
