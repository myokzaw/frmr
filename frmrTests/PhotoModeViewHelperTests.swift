import SwiftUI
import Testing
@testable import frmr

// Pure helpers behind the v5 / v5.2 editor, tool bar, scrubber, panels and
// prompts (frontend view helpers)
struct PhotoModeViewHelperTests {
    @Test func percentTextRounds() {
        #expect(ScrubberMath.percentText(0, scale: 100) == "0%")
        #expect(ScrubberMath.percentText(1, scale: 100) == "100%")
        #expect(ScrubberMath.percentText(1.5, scale: 100) == "150%")
        #expect(ScrubberMath.percentText(0.05, scale: 100) == "5%")
    }

    // v5.2 M5: value rings replace the "modified" dot
    @Test func valueRingFractions() {
        #expect(ToolRing.fraction(strength: 0) == 0)
        #expect(ToolRing.fraction(strength: 1.5) == 1)
        #expect(abs(ToolRing.fraction(strength: 1) - 2.0 / 3.0) < 1e-9)
        #expect(ToolRing.fraction(strength: 9) == 1)
        #expect(ToolRing.fraction(exposure: 0) == nil, "No ring at 0 EV")
        #expect(ToolRing.fraction(exposure: 1) == 0.5)
        #expect(ToolRing.fraction(exposure: -2) == 1)
    }

    // F-EXP: Exposure is the first tool; every effect carries a ring and a value
    @Test func editorToolItemsStartWithExposure() {
        var look = FilmLook.stockDefaults(for: .portrait400)
        let items = PhotoEditView.toolItems(look: look, exposureReadout: "0 EV")
        #expect(items.map(\.id) == ["exposure", "film", "print"] + FilmLook.Effect.allCases.map(\.rawValue))
        #expect(items[0].systemImage == "plus.forwardslash.minus")
        #expect(items[0].ring == nil)
        #expect(items.dropFirst(3).allSatisfy { $0.ring != nil && $0.value.hasSuffix("%") })

        look.exposure = 1
        let brighter = PhotoEditView.toolItems(look: look, exposureReadout: "+1.0 EV")
        #expect(brighter[0].ring == 0.5)
        #expect(brighter[0].value == "+1.0 EV")

        let off = PhotoEditView.toolItems(look: .stockDefaults(for: .none), exposureReadout: "0 EV")
        #expect(off.dropFirst(3).allSatisfy { $0.ring == nil && $0.value == "Off" }, "Off has no effects to ring")
    }

    // F-EXP scrubber: firm tick at 0, taller at whole stops, ⅓-stop notches
    @Test func exposureScaleTicks() {
        let scale = ScrubberScale.exposure
        let count = ScrubberMath.stepCount(in: scale.range, step: scale.step)
        #expect(count == 12, "−2…+2 EV in thirds")
        let kinds = (0...count).map {
            ScrubberMath.tickKind(at: $0, in: scale.range, step: scale.step, hapticStep: scale.majorStep, reference: scale.reference)
        }
        #expect(kinds[6] == .reference)
        #expect(kinds.filter { $0 == .reference }.count == 1)
        #expect(kinds[0] == .major && kinds[3] == .major && kinds[9] == .major && kinds[12] == .major)
        #expect(kinds[1] == .minor && kinds[2] == .minor)
        #expect(scale.fillsFromReference)
        #expect(!ScrubberScale.strength.fillsFromReference)
    }

    // BUG-V51-03: an unreadable linked-entry count asks both ways
    @Test func deletePromptsAskBothWaysWhenTheCountIsUnknown() {
        #expect(RollPromptText.deleteTitle(photoCount: 1, linkedEntries: 0) == "Delete this photo? This can't be undone.")
        #expect(RollPromptText.deleteTitle(photoCount: 2, linkedEntries: 1).hasPrefix("1 diary entry is about these 2 photos"))
        #expect(RollPromptText.deleteTitle(photoCount: 1, linkedEntries: nil).hasPrefix("Diary entries may be about this photo"))
        #expect(RollPromptText.clearRollTitle(linkedEntries: 3).hasPrefix("3 diary entries are"))
        #expect(RollPromptText.clearRollTitle(linkedEntries: nil).hasPrefix("Diary entries may be"))
        #expect(!RollPromptText.asksAboutEntries(0))
        #expect(RollPromptText.asksAboutEntries(nil))
        #expect(RollPromptText.asksAboutEntries(2))
    }

    // The camera tab is the darkroom; the others are paper (tab tint)
    @Test func tabSurfaces() {
        #expect(AppTab.surface(for: .camera) == .darkroom)
        #expect(AppTab.surface(for: .library) == .paper)
        #expect(AppTab.surface(for: .settings) == .paper)
    }

    // The window and paper covers take the user's appearance choice only;
    // System is nil so SwiftUI follows the system setting
    @Test func appearanceChoiceMapsToPreferredScheme() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
        #expect(AppearanceMode(rawValue: "unknown")?.colorScheme == nil)
    }
}
