import SwiftUI
import Testing
import UIKit
@testable import frmr

// QA acceptance tests for v5.1 behaviours that had no test: the audit's
// contrast roles (v5.2 research §2.1), the 44 pt tap-target floor, and the
// walkthrough copy decision v5.1-8.

struct V51ContrastTests {
    private static func luminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func ratio(_ a: Color, _ b: Color) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test func darkTextOnTheAmberPrimaryFill() {
        // Save to roll, Save entry, Save (strip): .appBlack on .appAmber
        #expect(Self.ratio(.appBlack, .appAmber) >= 7)
    }
}

struct V51TapTargetTests {
    @Test func everyInteractiveControlIsAtLeast44Points() {
        let sizes: [(String, CGFloat)] = [
            ("chip", Constants.CameraUI.chipDiameter),
            ("secondary", Constants.CameraUI.secondaryButtonSize),
            ("mode segment", Constants.CameraUI.modeSegmentSize),
            ("top button", Constants.CameraUI.topButtonSize),
            ("last photo", Constants.CameraUI.lastPhotoSize),
            ("dial", Constants.CameraUI.dialHeight),
            ("glass button", Constants.ScrubberUI.glassButtonSize),
            ("target min", Constants.DesignUI.targetMin),
            ("glass (design)", Constants.DesignUI.buttonGlass),
            ("primary button", Constants.DesignUI.buttonPrimaryHeight),
            ("library segment", Constants.LibraryUI.segmentHeight),
            ("effect row", Constants.EffectSliderUI.rowMinHeight),
            ("reset", Constants.ScrubberUI.resetButtonSize),
            ("ruler", Constants.ScrubberUI.rulerHeight),
            ("stock chip", Constants.ReviewUI.stockChipHeight),
            ("download", Constants.ReviewUI.downloadButtonSize),
            ("swatch", Constants.StripUI.swatchTapTarget),
            ("roll toolbar", Constants.RollUI.toolbarButtonSize),
            ("skip", Constants.EditorUI.skipButtonHeight),
            ("tool item w", Constants.ScrubberUI.toolItemWidth),
            ("tool item h", Constants.ScrubberUI.toolItemHeight),
        ]
        for (name, size) in sizes {
            #expect(size >= 44, "\(name) is \(size) pt")
        }
    }
}

// v5.2 M0: every ThemePalette role pair, as a pure function over scheme,
// surface and Increase Contrast. Semi-transparent roles are composited over
// the background they sit on before measuring.
struct ThemeRoleContrastTests {
    struct Combo: CustomTestStringConvertible {
        let name: String
        let scheme: ColorScheme
        let surface: FrmrSurface
        let contrast: ColorSchemeContrast
        var testDescription: String { "\(name) \(contrast == .increased ? "increased" : "standard")" }
    }

    private static let combos: [Combo] = [ColorSchemeContrast.standard, .increased].flatMap { contrast in
        [
            Combo(name: "darkroom", scheme: .dark, surface: .darkroom, contrast: contrast),
            Combo(name: "paper light", scheme: .light, surface: .paper, contrast: contrast),
            Combo(name: "paper dark", scheme: .dark, surface: .paper, contrast: contrast),
        ]
    }

    private static func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private static func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    private static func flatten(_ color: Color, over backdrop: Color) -> (r: Double, g: Double, b: Double) {
        let top = rgba(color), under = rgba(backdrop)
        return (top.r * top.a + under.r * (1 - top.a),
                top.g * top.a + under.g * (1 - top.a),
                top.b * top.a + under.b * (1 - top.a))
    }

    /// Contrast of `fg` drawn on `bg`, where `bg` itself may be translucent over `base`.
    private static func ratio(_ fg: Color, on bg: Color, base: Color) -> Double {
        let ground = flatten(bg, over: base)
        let groundColor = Color(red: ground.r, green: ground.g, blue: ground.b)
        let a = luminance(flatten(fg, over: groundColor)), b = luminance(ground)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @Test(arguments: combos)
    func textRolesReachBodyContrastOnBackgroundAndSurface(combo: Combo) {
        let p = ThemePalette.resolve(for: combo.scheme, surface: combo.surface, contrast: combo.contrast)
        for (name, fg) in [("text", p.text), ("textMuted", p.textMuted), ("tint", p.tint), ("destructive", p.destructive)] {
            #expect(Self.ratio(fg, on: p.bg, base: p.bg) >= 4.5, "\(name) on bg, \(combo.testDescription)")
            #expect(Self.ratio(fg, on: p.surface, base: p.bg) >= 4.5, "\(name) on surface, \(combo.testDescription)")
        }
    }

    @Test(arguments: combos)
    func onAccentIsReadableOnTheAccentFill(combo: Combo) {
        let p = ThemePalette.resolve(for: combo.scheme, surface: combo.surface, contrast: combo.contrast)
        #expect(Self.ratio(p.onAccent, on: p.accentFill, base: p.bg) >= 4.5, "\(combo.testDescription)")
    }

    @Test(arguments: combos)
    func nonTextMarksReachThreeToOne(combo: Combo) {
        let p = ThemePalette.resolve(for: combo.scheme, surface: combo.surface, contrast: combo.contrast)
        #expect(Self.ratio(p.selectedIndicator, on: p.bg, base: p.bg) >= 3, "indicator on bg, \(combo.testDescription)")
        #expect(Self.ratio(p.selectedIndicator, on: p.surface, base: p.bg) >= 3, "indicator on surface, \(combo.testDescription)")
        // Amber is a fill, never a line on cream (1.59:1): only where it clears 3:1
        if combo.surface == .darkroom || combo.scheme == .dark {
            #expect(Self.ratio(p.accentFill, on: p.bg, base: p.bg) >= 3, "amber fill on bg, \(combo.testDescription)")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func increaseContrastNeverLowersTextContrast(scheme: ColorScheme) {
        let standard = ThemePalette.resolve(for: scheme, contrast: .standard)
        let increased = ThemePalette.resolve(for: scheme, contrast: .increased)
        for (std, inc) in [(standard.textMuted, increased.textMuted), (standard.tint, increased.tint), (standard.destructive, increased.destructive)] {
            #expect(Self.ratio(inc, on: standard.bg, base: standard.bg) >= Self.ratio(std, on: standard.bg, base: standard.bg))
        }
    }

    @Test func motionTokensFallBackUnderReduceMotion() {
        #expect(FrmrMotion.develop.animation(reduceMotion: true) == nil)
        for motion in FrmrMotion.allCases {
            #expect(motion.animation(reduceMotion: false) != nil)
        }
    }
}
