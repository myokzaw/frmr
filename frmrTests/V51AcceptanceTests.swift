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

    @Test(arguments: [ColorScheme.light, .dark])
    func accentAndDestructiveRolesReachTextContrastOnTheirSurfaces(scheme: ColorScheme) {
        let theme = ThemePalette.resolve(for: scheme)
        let accent = ThemePalette.accent(for: scheme)
        let destructive = ThemePalette.destructive(for: scheme)
        for surface in [theme.background, theme.card] {
            #expect(Self.ratio(accent, surface) >= 4.5, "accent on \(scheme)")
            #expect(Self.ratio(destructive, surface) >= 4.5, "destructive on \(scheme)")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func textOnAnAccentFillIsReadable(scheme: ColorScheme) {
        let fill = ThemePalette.accent(for: scheme)
        #expect(Self.ratio(ThemePalette.onAccent(for: scheme), fill) >= 4.5)
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
            ("glass small", Constants.ScrubberUI.glassButtonSmallSize),
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

struct V51WalkthroughCopyTests {
    @Test func theCameraStepPointsAtContinueToDiary() {
        #expect(CoachCopy.entries[.camera]?.body == "Shoot on film. Write about a photo with Continue to diary.")
    }

    @Test func everyStepHasCopyAndNoneMentionsTheRemovedDiaryMode() {
        for step in CoachStep.allCases {
            let copy = CoachCopy.entries[step]
            #expect(copy != nil)
            #expect(copy?.body.localizedCaseInsensitiveContains("diary mode") == false)
        }
    }
}
