import Testing
import Foundation
@testable import frmr

// v5.1 F8: the scrubber's arithmetic (0–150% in 5% ticks, haptic marks).
struct EffectScrubberTests {
    private let range = FilmLook.strengthRange
    private let step = Constants.ScrubberUI.step

    @Test func touchPositionsSnapToFivePercentAndClamp() {
        #expect(ScrubberMath.value(forX: -20, width: 300, in: range, step: step) == 0)
        #expect(ScrubberMath.value(forX: 900, width: 300, in: range, step: step) == range.upperBound)
        let mid = ScrubberMath.value(forX: 200, width: 300, in: range, step: step)
        #expect(abs(mid - 1.0) < 1e-9)
    }

    @Test func percentTextAndHapticMarks() {
        #expect(ScrubberMath.percentText(1, scale: 100) == "100%")
        #expect(ScrubberMath.percentText(1.5, scale: 100) == "150%")
        #expect(ScrubberMath.hapticIndex(for: 1.0, hapticStep: 0.1) == 10)
        #expect(ScrubberMath.hapticIndex(for: 0.94, hapticStep: 0.1) == 9)
    }

    @Test func ticksMarkEveryTenPercentAndTheReference() {
        let kind = { (i: Int) in ScrubberMath.tickKind(at: i, in: range, step: step, hapticStep: 0.1, reference: 1) }
        #expect(ScrubberMath.stepCount(in: range, step: step) == 30)
        #expect(kind(20) == .reference)
        #expect(kind(2) == .major)
        #expect(kind(1) == .minor)
    }
}
