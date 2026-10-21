import Testing
@testable import frmr

// Pure text helpers behind the v5 sliders and panels
struct PhotoModeViewHelperTests {
    @Test func percentTextRoundsAndClamps() {
        #expect(EffectSliderRow.percentText(0) == "0%")
        #expect(EffectSliderRow.percentText(1) == "100%")
        #expect(EffectSliderRow.percentText(1.5) == "150%")
        #expect(EffectSliderRow.percentText(0.05) == "5%")
        #expect(EffectSliderRow.percentText(9) == "150%")
        #expect(EffectSliderRow.percentText(-1) == "0%")
        #expect(EffectSliderRow.percentText(.nan) == "0%")
    }

    @Test func kelvinAndTintText() {
        #expect(WhiteBalancePanel.kelvinText(5600) == "5600K")
        #expect(WhiteBalancePanel.tintText(0) == "0")
        #expect(WhiteBalancePanel.tintText(12) == "+12")
        #expect(WhiteBalancePanel.tintText(-8) == "-8")
    }
}
