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

// v5.1 F8: one tick-mark scrubber adjusts whichever effect is selected,
// like the Photos editor — 0–150% in 5% ticks with a value readout, a light
// haptic every 10% and a stronger one at 100% (the stock default). Touch or
// drag anywhere on the ruler; double-tap, or the small reset icon, returns
// to the default. For VoiceOver the ruler is one adjustable element (5% per
// swipe), and Reset is a named action.
struct EffectScrubber: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    let hint: String
    let identifier: String
    let textColor: Color
    let tint: Color
    var isEnabled = true
    var range: ClosedRange<Double> = FilmLook.strengthRange

    private typealias UI = Constants.ScrubberUI

    private struct HapticMark: Equatable {
        let title: String
        let index: Int
    }

    private var isAtDefault: Bool { abs(value - defaultValue) < UI.step / 2 }
    private var percentText: String { ScrubberMath.percentText(value, scale: UI.percentScale) }

    var body: some View {
        VStack(spacing: UI.headerSpacing) {
            header
            ruler
        }
        .opacity(isEnabled ? 1 : UI.disabledOpacity)
        .disabled(!isEnabled)
    }

    private var header: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(textColor)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(percentText)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(textColor)
                .accessibilityHidden(true)
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: Constants.CameraUI.chipIconSize, weight: .semibold))
                    .foregroundStyle(textColor)
                    .frame(width: UI.resetButtonSize, height: UI.resetButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isAtDefault ? UI.disabledOpacity : 1)
            .disabled(isAtDefault)
            .accessibilityLabel("Reset \(title)")
            .accessibilityHint("Returns to this film's default")
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
                        set(ScrubberMath.value(forX: drag.location.x - UI.rulerInset, width: trackWidth, in: range, step: UI.step))
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { reset() })
        }
        .frame(height: UI.rulerHeight)
        // Switching tool changes the value without a scrub: no tick for that
        .sensoryFeedback(trigger: HapticMark(title: title, index: ScrubberMath.hapticIndex(for: value, hapticStep: UI.hapticStep))) { old, new in
            guard old.title == new.title else { return nil }
            return new.index == ScrubberMath.hapticIndex(for: UI.referenceValue, hapticStep: UI.hapticStep)
                ? .impact(weight: .medium)
                : .impact(weight: .light)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(percentText)
        .accessibilityHint(hint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + UI.step)
            case .decrement: set(value - UI.step)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset to default", reset)
        .accessibilityIdentifier(identifier)
    }

    private func marker(trackWidth: CGFloat) -> some View {
        let position = ScrubberMath.fraction(of: value, in: range) * trackWidth + UI.rulerInset
        return GeometryReader { geometry in
            Capsule()
                .fill(tint)
                .frame(width: UI.markerWidth, height: UI.markerHeight)
                .position(x: position, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize) {
        let count = ScrubberMath.stepCount(in: range, step: UI.step)
        let trackWidth = size.width - UI.rulerInset * 2
        for index in 0...count {
            let x = UI.rulerInset + trackWidth * CGFloat(index) / CGFloat(count)
            let tickValue = range.lowerBound + Double(index) * UI.step
            let kind = ScrubberMath.tickKind(
                at: index, in: range, step: UI.step, hapticStep: UI.hapticStep, reference: UI.referenceValue
            )
            let height: CGFloat
            switch kind {
            case .reference: height = UI.referenceTickHeight
            case .major: height = UI.majorTickHeight
            case .minor: height = UI.minorTickHeight
            }
            let isReached = tickValue <= value + UI.step / 2
            let opacity = isReached ? UI.activeTickOpacity : UI.idleTickOpacity
            let color = kind == .reference ? tint : textColor
            let rect = CGRect(x: x - UI.tickWidth / 2, y: (size.height - height) / 2, width: UI.tickWidth, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: UI.tickWidth / 2), with: .color(color.opacity(kind == .reference ? 1 : opacity)))
        }
    }

    private func set(_ newValue: Double) {
        let snapped = ScrubberMath.snapped(newValue, in: range, step: UI.step)
        if snapped != value { value = snapped }
    }

    private func reset() {
        value = defaultValue
    }
}
