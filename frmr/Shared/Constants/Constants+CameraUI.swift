import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Camera UI (project.md §2, screens 1 & 3; v5.1 F8/F9; v5.2 S1/S2)
    enum CameraUI {
        private typealias D = Constants.DesignUI

        // Shutter row (the shutter itself is DesignUI.shutterOuter/Inner)
        static let shutterRingWidth: CGFloat = 3
        static let shutterBottomPadding: CGFloat = D.Space.s
        static let chipSpacing: CGFloat = D.Space.s
        static let chipInactiveOpacity: CGFloat = 0.14

        // Rotate-in-place chrome: every chip is a fixed circle, so turning it
        // about its centre never overflows its frame
        static let chipDiameter: CGFloat = D.targetMin
        static let chipIconSize: CGFloat = 16

        // v3 F1 — device-side diagnosis switch: renders the live
        // rotation angle over the camera so a device photograph can prove
        // what actually reaches the views (DEBUG builds only)
        static let chromeDebugOverlayEnabled = false
        // Read by V51AcceptanceTests' 44-pt floor
        static let secondaryButtonSize: CGFloat = D.targetMin
        static let disabledControlOpacity: CGFloat = 0.5
        static let permissionTextMaxWidth: CGFloat = 320

        // Landscape dock on the far right edge
        static let dockSpacing: CGFloat = D.Space.s
        static let dockTrailingPadding: CGFloat = D.Space.m

        // v5.1 F8 top bar: mode switch left, WB and EV right
        static let screenMargin: CGFloat = D.gutter
        static let topBarTopPadding: CGFloat = D.Space.s
        static let modeSegmentSize: CGFloat = D.targetMin
        static let modeSwitchPadding: CGFloat = 3
        static let topButtonSize: CGFloat = D.buttonGlass
        static let topButtonSpacing: CGFloat = D.Space.s
        static let bottomStackSpacing: CGFloat = D.Space.m
        // A WB/EV value ("4300K") shrinks a little rather than leave its disc
        static let valueButtonMinScale: CGFloat = 0.6

        // v5.2 S1: the viewfinder is 3:4 (width over height) below the chrome
        static let viewfinderAspect: CGFloat = 3.0 / 4.0

        // v5.2 S1 HUD: the value flash in the upper third of the viewfinder
        static let hudTopPadding: CGFloat = 120
        static let hudOverlayTopPadding: CGFloat = 40
        static let hudShadowOpacity: CGFloat = 0.5
        static let hudShadowRadius: CGFloat = 6
        static let hudStartScale: CGFloat = 0.92

        // v5.2 S1 stock dial: a swatch over each code, faded edges
        static let dialItemWidth: CGFloat = 60
        static let dialHeight: CGFloat = 52
        static let dialNameOpacity: CGFloat = 0.75
        static let dialUnselectedOpacity: CGFloat = 0.6
        static let dialNameSpacing: CGFloat = D.Space.xs
        static let dialFadeFraction: CGFloat = 0.08
        static let dialSwatchSpacing: CGFloat = 3
        static let dialSwatchWidth: CGFloat = 24
        static let dialSwatchHeight: CGFloat = 12
        static let dialSwatchCornerRadius: CGFloat = 3
        static let dialSwatchRim: CGFloat = 0.5
        static let dialSwatchRimOpacity: CGFloat = 0.35
        static let dialSwatchSelectedRing: CGFloat = 1.5
        static let dialCodeMinScale: CGFloat = 0.7

        // v5.1 F8 WB / EV sheets (one open at a time)
        static let sheetPadding: CGFloat = D.Space.xl
        static let panelSpacing: CGFloat = D.Space.m
        static let whiteBalanceSheetHeight: CGFloat = 270
        static let exposureSheetHeight: CGFloat = 150
        static let panelSliderLabelWidth: CGFloat = 52
        static let panelValueWidth: CGFloat = 56
        static let kelvinSliderStep: Double = 50
        static let tintSliderStep: Double = 1

        // v5: last Roll photo beside the shutter
        static let lastPhotoSize: CGFloat = D.targetMin
        static let lastPhotoBorderWidth: CGFloat = 1
        static let lastPhotoBorderOpacity: CGFloat = 0.6

        // v5.2 S2 Film strip: a paper mini-strip of four 4:5 frames in the
        // thumbnail's place, and a sheet with the slots and actions
        static let miniStripWidth: CGFloat = D.targetMin
        static let miniStripHeight: CGFloat = 64
        static let miniStripPadding: CGFloat = 3
        static let miniStripFrameSpacing: CGFloat = 2
        static let miniStripBadgeOffset: CGFloat = 8
        static let stripFrameAspect: CGFloat = 4.0 / 5.0
        static let stripSlotSpacing: CGFloat = D.Space.s
        static let stripEmptySlotOpacity: CGFloat = 0.18
        static let slotsSheetHeight: CGFloat = 330
        // iOS 26 draws a partial-height sheet slightly scaled down (about
        // 96%), so icons in it start a little over the 44-pt floor
        static let sheetIconSize: CGFloat = 48
        static let rollPickerColumns = 3
    }
}
