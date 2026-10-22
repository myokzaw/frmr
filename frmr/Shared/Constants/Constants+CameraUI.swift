import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Camera UI (project.md §2, screens 1 & 3)
    enum CameraUI {
        static let shutterOuterDiameter: CGFloat = 76
        static let shutterInnerDiameter: CGFloat = 64
        static let shutterRingWidth: CGFloat = 4
        static let shutterBottomPadding: CGFloat = 28
        static let chipFontSize: CGFloat = 12
        static let chipHorizontalPadding: CGFloat = 12
        static let chipVerticalPadding: CGFloat = 7
        static let chipSpacing: CGFloat = 8
        static let chipInactiveOpacity: CGFloat = 0.14
        static let modePillFontSize: CGFloat = 13
        static let modePillPadding: CGFloat = 4

        // Rotate-in-place chrome (replaces v3 F2/F4): every chip is a fixed
        // circle, so turning it about its centre never overflows its frame
        static let chipDiameter: CGFloat = 44
        static let chipIconSize: CGFloat = 16

        // v3 F3 — collapsible white balance
        static let wbExpandAnimationDuration: TimeInterval = 0.2

        // v4 F9 — Film chip: glyph over a short stock code inside the 44pt
        // circle; the content width keeps "M3.2K" clear of the edge
        static let filmChipSymbolSize: CGFloat = 10
        static let filmChipCodeFontSize: CGFloat = 10
        static let filmChipCodeMinScale: CGFloat = 0.7
        static let filmChipLineSpacing: CGFloat = 1
        static let filmChipContentWidth: CGFloat = 36

        // v3 F1 — device-side diagnosis switch: renders the live
        // rotation angle over the camera so a device photograph can prove
        // what actually reaches the views (DEBUG builds only)
        static let chromeDebugOverlayEnabled = false
        static let slotSize: CGFloat = 64
        static let slotCornerRadius: CGFloat = 8
        static let slotDashWidth: CGFloat = 1.5
        static let slotDashLength: CGFloat = 4
        static let slotBorderOpacity: CGFloat = 0.3
        static let slotSpacing: CGFloat = 10
        static let secondaryButtonSize: CGFloat = 44
        static let secondaryButtonCornerRadius: CGFloat = 9
        static let generateButtonVerticalPadding: CGFloat = 9
        static let disabledControlOpacity: CGFloat = 0.5
        static let captionFontSize: CGFloat = 11
        static let captionOpacity: CGFloat = 0.45
        static let captionMaxWidth: CGFloat = 300
        static let captionMinScale: CGFloat = 0.7
        static let permissionTextMaxWidth: CGFloat = 280
        static let permissionTextMinScale: CGFloat = 0.8

        // Landscape dock on the far right edge
        static let dockSpacing: CGFloat = 10
        static let dockTrailingPadding: CGFloat = 12

        // v5 F2 stock dial: a snapping strip of fixed-width detents above
        // the shutter; the strip never turns, each code label does
        static let dialItemWidth: CGFloat = 60
        static let dialHeight: CGFloat = 44
        static let dialCodeFontSize: CGFloat = 14
        static let dialUnselectedOpacity: CGFloat = 0.5
        static let dialSelectedScale: CGFloat = 1.15
        static let dialTickWidth: CGFloat = 2
        static let dialTickHeight: CGFloat = 8
        static let dialCaptionSpacing: CGFloat = 4
        static let dialSnapAnimationDuration: TimeInterval = 0.2

        // v5 F3 Photo-mode WB / EV panels (one open at a time)
        static let panelCornerRadius: CGFloat = 18
        static let panelPadding: CGFloat = 12
        static let panelSpacing: CGFloat = 10
        static let panelBackgroundOpacity: CGFloat = 0.55
        static let panelHorizontalMargin: CGFloat = 16
        static let panelMaxWidth: CGFloat = 420
        static let panelSliderLabelWidth: CGFloat = 52
        static let panelValueWidth: CGFloat = 56
        static let kelvinSliderStep: Double = 50
        static let tintSliderStep: Double = 1
        static let panelAnimationDuration: TimeInterval = 0.2

        // v5: last Roll photo beside the shutter
        static let lastPhotoSize: CGFloat = 44
        static let lastPhotoCornerRadius: CGFloat = 10
        static let lastPhotoBorderWidth: CGFloat = 1.5
        static let lastPhotoBorderOpacity: CGFloat = 0.8
    }
}
