import Testing
import Foundation
@testable import frmr

// v5.1 F8: the scrubber's arithmetic (0–150% in 5% ticks, haptic marks).
struct EffectScrubberTests {
    private let range = FilmLook.strengthRange
    private let step = Constants.ScrubberUI.step

    @Test func dragIsRelativeSnappedClampedAndLeftRaises() {
        let spacing = Constants.ScrubberUI.strengthTickSpacing
        let drag = { (t: CGFloat, from: Double) in ScrubberMath.value(afterDrag: t, from: from, spacing: spacing, step: step, range: range) }
        #expect(drag(0, 1.0) == 1.0)
        #expect(abs(drag(-spacing, 1.0) - 1.05) < 1e-9)
        #expect(abs(drag(spacing, 1.0) - 0.95) < 1e-9)
        #expect(abs(drag(-spacing * 0.4, 1.0) - 1.0) < 1e-9)
        #expect(drag(-5000, 1.0) == range.upperBound)
        #expect(drag(5000, 1.0) == 0)
    }

    @Test func fullRangeTakesACoupleOfSwipesOnEveryRuler() {
        // A swipe is ~300pt: a few swipes end to end at most
        for scale in [ScrubberScale.strength, .exposure, .tone, .cameraExposure] {
            let notches = ScrubberMath.stepCount(in: scale.range, step: scale.step)
            #expect(CGFloat(notches) * scale.tickSpacing <= 1300, "\(scale.range)")
            #expect(scale.tickSpacing >= 6)
        }
    }

    @Test func visibleTicksCoverOnlyTheViewAndStayInRange() throws {
        let tone = ScrubberScale.tone
        let mid = try #require(ScrubberMath.visibleTicks(around: 0, width: 300, spacing: 6, in: tone.range, step: tone.step))
        #expect(mid.count <= 53 && mid.contains(100))
        let start = try #require(ScrubberMath.visibleTicks(around: -100, width: 300, spacing: 6, in: tone.range, step: tone.step))
        #expect(start.lowerBound == 0)
        let end = try #require(ScrubberMath.visibleTicks(around: 100, width: 300, spacing: 6, in: tone.range, step: tone.step))
        #expect(end.upperBound == 200)
        #expect(ScrubberMath.visibleTicks(around: 0, width: 0, spacing: 6, in: tone.range, step: tone.step) == nil)
    }

    @Test func firmNotchesAreReferenceAndFirmSteps() {
        let tone = ScrubberScale.tone
        let firm = { (v: Double) in ScrubberMath.isFirm(index: ScrubberMath.hapticIndex(for: v, hapticStep: tone.step), scale: tone) }
        #expect(firm(0) && firm(50) && firm(-50) && !firm(1) && !firm(10))
        let ev = ScrubberScale.cameraExposure
        let evFirm = { (v: Double) in ScrubberMath.isFirm(index: ScrubberMath.hapticIndex(for: v, hapticStep: ev.step), scale: ev) }
        #expect(evFirm(0) && evFirm(1) && evFirm(-2) && !evFirm(1.0 / 3))
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
