import SwiftUI

/// The scrubber's arithmetic, kept out of the view so it is unit-testable.
nonisolated enum ScrubberMath {
    /// How many 5% steps the range holds (30 for 0…150%).
    static func stepCount(in range: ClosedRange<Double>, step: Double) -> Int {
        Int(((range.upperBound - range.lowerBound) / step).rounded())
    }

    /// The nearest step inside the range.
    static func snapped(_ value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let steps = ((value - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }

    /// The unsnapped, clamped value after the ruler is dragged `translation`
    /// points from where the drag began. The ruler follows the finger, so
    /// dragging left reads a higher value (as in Photos).
    static func rawValue(
        afterDrag translation: CGFloat, from start: Double, spacing: CGFloat, step: Double, range: ClosedRange<Double>
    ) -> Double {
        guard spacing > 0 else { return start }
        let moved = start - Double(translation / spacing) * step
        return min(max(moved, range.lowerBound), range.upperBound)
    }

    /// `rawValue(afterDrag:...)` snapped to a notch; no movement, no change.
    static func value(
        afterDrag translation: CGFloat, from start: Double, spacing: CGFloat, step: Double, range: ClosedRange<Double>
    ) -> Double {
        snapped(rawValue(afterDrag: translation, from: start, spacing: spacing, step: step, range: range), in: range, step: step)
    }

    /// The tick indices (0 = range start) that fall inside a ruler `width`
    /// wide when `value` sits under its centre; nil when none do.
    static func visibleTicks(
        around value: Double, width: CGFloat, spacing: CGFloat, in range: ClosedRange<Double>, step: Double
    ) -> ClosedRange<Int>? {
        let count = stepCount(in: range, step: step)
        guard spacing > 0, width > 0, count >= 0 else { return nil }
        let center = (value - range.lowerBound) / step
        let half = Double(width / 2 / spacing)
        let low = max(Int((center - half).rounded(.down)), 0)
        let high = min(Int((center + half).rounded(.up)), count)
        return low <= high ? low...high : nil
    }

    /// Which notch the value sits on; the haptic fires when it changes.
    static func hapticIndex(for value: Double, hapticStep: Double) -> Int {
        Int((value / hapticStep).rounded())
    }

    /// "100%", "0%", "150%".
    static func percentText(_ value: Double, scale: Double) -> String {
        "\(Int((value * scale).rounded()))%"
    }

    /// Whether notch `index` is the reference or a firm step.
    static func isFirm(index: Int, scale: ScrubberScale) -> Bool {
        let value = Double(index) * scale.step
        if abs(value - scale.reference) < scale.step / 2 { return true }
        guard let firmStep = scale.firmStep else { return false }
        let firm = value / firmStep
        return abs(firm - firm.rounded()) * firmStep < scale.step / 2
    }

    /// Height class of the tick at `index`: the reference mark, every
    /// 10%, or a plain 5%.
    enum TickKind { case reference, major, minor }

    static func tickKind(
        at index: Int, in range: ClosedRange<Double>, step: Double, hapticStep: Double, reference: Double, firmStep: Double? = nil
    ) -> TickKind {
        let value = range.lowerBound + Double(index) * step
        if abs(value - reference) < step / 2 { return .reference }
        if let firmStep {
            let firm = value / firmStep
            if abs(firm - firm.rounded()) * firmStep < step / 2 { return .reference }
        }
        let marks = value / hapticStep
        return abs(marks - marks.rounded()) < 0.01 ? .major : .minor
    }
}

/// The ruler a scrubber draws: its range, notch, the ticks that stand out
/// and the firm reference tick.
nonisolated struct ScrubberScale: Equatable {
    var range: ClosedRange<Double>
    /// One notch: a drag snaps to it and VoiceOver moves by it.
    var step: Double
    /// Taller ticks every this much.
    var majorStep: Double
    /// Points between two ticks: small enough that a short move is one
    /// notch, wide enough that the whole range takes a couple of swipes.
    var tickSpacing: CGFloat
    /// The firm tick and the stronger haptic.
    var reference: Double
    /// Lit ticks run from the reference to the value (exposure either side
    /// of 0) rather than from the start of the ruler.
    var fillsFromReference = false
    /// More firm ticks (and stronger haptics) at every multiple of this, as
    /// well as at the reference (Shadows and Highlights: ±50, exposure:
    /// whole stops).
    var firmStep: Double?
    /// What VoiceOver moves by per swipe; nil is one `step`.
    var accessibilityStep: Double?

    /// Effect strengths: 0–150% in 5% ticks, taller every 10%, firm at 100%.
    static let strength = ScrubberScale(
        range: FilmLook.strengthRange,
        step: Constants.ScrubberUI.step,
        majorStep: Constants.ScrubberUI.hapticStep,
        tickSpacing: Constants.ScrubberUI.strengthTickSpacing,
        reference: Constants.ScrubberUI.referenceValue
    )

    /// Exposure (v5.2 F-EXP): −2…+2 EV, a light tick and haptic each ⅓
    /// stop, taller at whole stops, firm at 0.
    static let exposure = ScrubberScale(
        range: FilmLook.exposureRange,
        step: FilmLook.exposureStep,
        majorStep: Constants.ScrubberUI.exposureMajorStep,
        tickSpacing: Constants.ScrubberUI.exposureTickSpacing,
        reference: 0,
        fillsFromReference: true,
        firmStep: Constants.ScrubberUI.exposureMajorStep
    )

    /// The camera's exposure compensation: the same ruler over the
    /// camera's own range and ⅓-stop step.
    static let cameraExposure = ScrubberScale(
        range: Double(Constants.Camera.exposureBiasMin)...Double(Constants.Camera.exposureBiasMax),
        step: Double(Constants.Camera.exposureStep),
        majorStep: Constants.ScrubberUI.exposureMajorStep,
        tickSpacing: Constants.ScrubberUI.exposureTickSpacing,
        reference: 0,
        fillsFromReference: true,
        firmStep: Constants.ScrubberUI.exposureMajorStep
    )

    /// The camera's digital zoom (F-122-G): 1...3x in 0.2 steps, firm at
    /// each whole x.
    static let cameraZoom = ScrubberScale(
        range: Double(Constants.Camera.minZoomFactor)...Double(Constants.Camera.maxDigitalZoom),
        step: Double(Constants.Camera.zoomStep),
        majorStep: Constants.ScrubberUI.zoomMajorStep,
        tickSpacing: Constants.ScrubberUI.zoomTickSpacing,
        reference: Double(Constants.Camera.minZoomFactor),
        firmStep: Constants.ScrubberUI.zoomMajorStep
    )

    /// Shadows and Highlights (F-122-C): -100...+100, a tick per 1, taller
    /// every 10, firm at 0 and ±50, VoiceOver in steps of 5.
    static let tone = ScrubberScale(
        range: FilmLook.toneRange,
        step: FilmLook.toneStep,
        majorStep: Constants.ScrubberUI.toneMajorStep,
        tickSpacing: Constants.ScrubberUI.toneTickSpacing,
        reference: 0,
        fillsFromReference: true,
        firmStep: Constants.ImageProcessing.Film.ToneControl.majorStep,
        accessibilityStep: Constants.ImageProcessing.Film.ToneControl.accessibilityStep
    )
}

// v5.1 F8: one tick-mark scrubber adjusts whichever tool is selected, like
// the Photos editor: a ruler with a value readout, a light haptic per notch
// and a stronger one at the reference (100% for an effect, 0 EV for
// exposure). The marker stays at the centre and the ruler slides under it:
// drag left to raise the value, right to lower it, relative to where the
// drag began, so a touch alone changes nothing and small moves give single
// steps. Double-tap, or the small reset icon, returns to the default. For VoiceOver the ruler is one
// adjustable element (one notch per swipe), and Reset is a named action.
struct EffectScrubber: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let hint: String
    let identifier: String
    let textColor: Color
    let tint: Color
    var isEnabled = true
    var scale: ScrubberScale = .strength
    /// The readout; nil shows a percentage.
    var valueText: String?
    var resetHint = "Returns to this film's default"
    /// False where the surrounding panel already shows title, readout and
    /// its own steps (the camera's exposure sheet).
    var showsHeader = true
    /// The unsnapped value under the finger while the ruler is dragged, and
    /// nil when the drag ends (the camera's viewfinder follows it smoothly).
    var onLiveValue: ((Double?) -> Void)?

    private typealias UI = Constants.ScrubberUI

    /// Where the drag began and the unsnapped value under the finger, so
    /// the ruler glides between notches.
    @State private var dragStart: Double?
    @State private var dragPosition: Double?

    private struct HapticMark: Equatable {
        let title: String
        let index: Int
    }

    private var isAtDefault: Bool { abs(value - defaultValue) < scale.step / 2 }
    private var readout: String { valueText ?? ScrubberMath.percentText(value, scale: UI.percentScale) }

    var body: some View {
        VStack(spacing: UI.headerSpacing) {
            if showsHeader { header }
            ruler
        }
        .opacity(isEnabled ? 1 : UI.disabledOpacity)
        .disabled(!isEnabled)
    }

    private var header: some View {
        HStack(spacing: Constants.DesignUI.Space.s) {
            Text(title)
                .font(.frmrLabel)
                .foregroundStyle(textColor)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(readout)
                .font(.frmrValue)
                .foregroundStyle(textColor)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
                .accessibilityIdentifier("\(identifier).readout")
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: UI.resetIconSize, weight: .medium))
                    .foregroundStyle(textColor)
                    .frame(width: UI.resetButtonSize, height: UI.resetButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isAtDefault ? UI.disabledOpacity : 1)
            .disabled(isAtDefault)
            .accessibilityLabel("Reset \(title)")
            .accessibilityHint(resetHint)
            .accessibilityIdentifier("\(identifier).reset")
        }
        .frame(minHeight: UI.resetButtonSize)
    }

    private var ruler: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    drawTicks(in: &context, size: size)
                }
                // The marker never moves; the ruler does
                Capsule()
                    .fill(tint)
                    .frame(width: UI.markerWidth, height: UI.markerHeight)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let position = ScrubberMath.rawValue(
                            afterDrag: drag.translation.width, from: start, spacing: scale.tickSpacing,
                            step: scale.step, range: scale.range)
                        dragPosition = position
                        onLiveValue?(position)
                        set(position)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragPosition = nil
                        onLiveValue?(nil)
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        }
        .frame(height: UI.rulerHeight)
        .clipped()
        // A tick per notch; switching tool changes the value without a
        // scrub, so no tick for that
        .sensoryFeedback(trigger: HapticMark(title: title, index: ScrubberMath.hapticIndex(for: value, hapticStep: scale.step))) { old, new in
            guard old.title == new.title else { return nil }
            return ScrubberMath.isFirm(index: new.index, scale: scale)
                ? .impact(weight: .medium)
                : .selection
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(readout)
        .accessibilityHint(hint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + (scale.accessibilityStep ?? scale.step))
            case .decrement: set(value - (scale.accessibilityStep ?? scale.step))
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset to default", reset)
        .accessibilityIdentifier(identifier)
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let position = dragPosition ?? value
        guard let visible = ScrubberMath.visibleTicks(
            around: position, width: size.width, spacing: scale.tickSpacing, in: scale.range, step: scale.step
        ) else { return }
        // Ticks fill from the reference towards the value, so a negative EV
        // reads as a bar to the left of 0
        let low = min(value, scale.reference) - scale.step / 2
        let high = max(value, scale.reference) + scale.step / 2
        for index in visible {
            let tickValue = scale.range.lowerBound + Double(index) * scale.step
            let x = size.width / 2 + CGFloat((tickValue - position) / scale.step) * scale.tickSpacing
            let kind = ScrubberMath.tickKind(
                at: index, in: scale.range, step: scale.step, hapticStep: scale.majorStep, reference: scale.reference,
                firmStep: scale.firmStep
            )
            let height: CGFloat
            switch kind {
            case .reference: height = UI.referenceTickHeight
            case .major: height = UI.majorTickHeight
            case .minor: height = UI.minorTickHeight
            }
            let isReached = scale.fillsFromReference
                ? tickValue >= low && tickValue <= high
                : tickValue <= value + scale.step / 2
            let opacity = isReached ? UI.activeTickOpacity : UI.idleTickOpacity
            let color = kind == .reference ? tint : textColor
            let rect = CGRect(x: x - UI.tickWidth / 2, y: (size.height - height) / 2, width: UI.tickWidth, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: UI.tickWidth / 2), with: .color(color.opacity(kind == .reference ? 1 : opacity)))
        }
    }

    private func set(_ newValue: Double) {
        let snapped = ScrubberMath.snapped(newValue, in: scale.range, step: scale.step)
        if snapped != value { value = snapped }
    }

    private func reset() {
        value = defaultValue
    }
}
