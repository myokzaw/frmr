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

    /// A touch at `x` along a ruler `width` wide, as a snapped value.
    static func value(forX x: CGFloat, width: CGFloat, in range: ClosedRange<Double>, step: Double) -> Double {
        guard width > 0 else { return range.lowerBound }
        let fraction = min(max(Double(x / width), 0), 1)
        return snapped(range.lowerBound + fraction * (range.upperBound - range.lowerBound), in: range, step: step)
    }

    /// 0…1 position of `value` along the ruler.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Which 10% mark the value sits on; the haptic fires when it changes.
    static func hapticIndex(for value: Double, hapticStep: Double) -> Int {
        Int((value / hapticStep).rounded())
    }

    /// "100%", "0%", "150%".
    static func percentText(_ value: Double, scale: Double) -> String {
        "\(Int((value * scale).rounded()))%"
    }

    /// Height class of the tick at `index`: the reference mark, every
    /// 10%, or a plain 5%.
    enum TickKind { case reference, major, minor }

    static func tickKind(at index: Int, in range: ClosedRange<Double>, step: Double, hapticStep: Double, reference: Double) -> TickKind {
        let value = range.lowerBound + Double(index) * step
        if abs(value - reference) < step / 2 { return .reference }
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
    /// A light haptic every this much.
    var hapticStep: Double
    /// The firm tick and the stronger haptic.
    var reference: Double
    /// Lit ticks run from the reference to the value (exposure either side
    /// of 0) rather than from the start of the ruler.
    var fillsFromReference = false

    /// Effect strengths: 0–150% in 5% ticks, taller every 10%, firm at 100%.
    static let strength = ScrubberScale(
        range: FilmLook.strengthRange,
        step: Constants.ScrubberUI.step,
        majorStep: Constants.ScrubberUI.hapticStep,
        hapticStep: Constants.ScrubberUI.hapticStep,
        reference: Constants.ScrubberUI.referenceValue
    )

    /// Exposure (v5.2 F-EXP): −2…+2 EV, a light tick and haptic each ⅓
    /// stop, taller at whole stops, firm at 0.
    static let exposure = ScrubberScale(
        range: FilmLook.exposureRange,
        step: FilmLook.exposureStep,
        majorStep: Constants.ScrubberUI.exposureMajorStep,
        hapticStep: FilmLook.exposureStep,
        reference: 0,
        fillsFromReference: true
    )
}

// v5.1 F8: one tick-mark scrubber adjusts whichever tool is selected, like
// the Photos editor: a ruler with a value readout, a light haptic per notch
// and a stronger one at the reference (100% for an effect, 0 EV for
// exposure). Touch or drag anywhere on the ruler; double-tap, or the small
// reset icon, returns to the default. For VoiceOver the ruler is one
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

    private typealias UI = Constants.ScrubberUI

    private struct HapticMark: Equatable {
        let title: String
        let index: Int
    }

    private var isAtDefault: Bool { abs(value - defaultValue) < scale.step / 2 }
    private var readout: String { valueText ?? ScrubberMath.percentText(value, scale: UI.percentScale) }

    var body: some View {
        VStack(spacing: UI.headerSpacing) {
            header
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
            let trackWidth = max(geometry.size.width - UI.rulerInset * 2, 1)
            ZStack {
                Canvas { context, size in
                    drawTicks(in: &context, size: size)
                }
                marker(trackWidth: trackWidth)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        set(ScrubberMath.value(forX: drag.location.x - UI.rulerInset, width: trackWidth, in: scale.range, step: scale.step))
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        }
        .frame(height: UI.rulerHeight)
        // Switching tool changes the value without a scrub: no tick for that
        .sensoryFeedback(trigger: HapticMark(title: title, index: ScrubberMath.hapticIndex(for: value, hapticStep: scale.hapticStep))) { old, new in
            guard old.title == new.title else { return nil }
            return new.index == ScrubberMath.hapticIndex(for: scale.reference, hapticStep: scale.hapticStep)
                ? .impact(weight: .medium)
                : .impact(weight: .light)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(readout)
        .accessibilityHint(hint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + scale.step)
            case .decrement: set(value - scale.step)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset to default", reset)
        .accessibilityIdentifier(identifier)
    }

    private func marker(trackWidth: CGFloat) -> some View {
        let position = ScrubberMath.fraction(of: value, in: scale.range) * trackWidth + UI.rulerInset
        return GeometryReader { geometry in
            Capsule()
                .fill(tint)
                .frame(width: UI.markerWidth, height: UI.markerHeight)
                .position(x: position, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let count = ScrubberMath.stepCount(in: scale.range, step: scale.step)
        guard count > 0 else { return }
        let trackWidth = size.width - UI.rulerInset * 2
        // Ticks fill from the reference towards the value, so a negative EV
        // reads as a bar to the left of 0
        let low = min(value, scale.reference) - scale.step / 2
        let high = max(value, scale.reference) + scale.step / 2
        for index in 0...count {
            let x = UI.rulerInset + trackWidth * CGFloat(index) / CGFloat(count)
            let tickValue = scale.range.lowerBound + Double(index) * scale.step
            let kind = ScrubberMath.tickKind(
                at: index, in: scale.range, step: scale.step, hapticStep: scale.majorStep, reference: scale.reference
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
