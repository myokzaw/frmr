import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Camera UI (project.md §2, screens 1 & 3; v5.1 F8/F9)
    enum CameraUI {
        // Shutter: smaller and quieter than v5 so the bottom stack breathes
        static let shutterOuterDiameter: CGFloat = 72
        static let shutterInnerDiameter: CGFloat = 60
        static let shutterRingWidth: CGFloat = 3
        static let shutterBottomPadding: CGFloat = 20
        static let chipFontSize: CGFloat = 12
        static let chipSpacing: CGFloat = 8
        // Still read by the Library views (restyle agent's files)
        static let chipHorizontalPadding: CGFloat = 12
        static let chipVerticalPadding: CGFloat = 7
        static let generateButtonVerticalPadding: CGFloat = 9
        static let chipInactiveOpacity: CGFloat = 0.14

        // Rotate-in-place chrome (replaces v3 F2/F4): every chip is a fixed
        // circle, so turning it about its centre never overflows its frame
        static let opaqueGlassOpacity: CGFloat = 0.92
        static let chipDiameter: CGFloat = 44
        static let chipIconSize: CGFloat = 16
        static let filmChipLineSpacing: CGFloat = 1

        // v3 F1 — device-side diagnosis switch: renders the live
        // rotation angle over the camera so a device photograph can prove
        // what actually reaches the views (DEBUG builds only)
        static let chromeDebugOverlayEnabled = false
        static let secondaryButtonSize: CGFloat = 44
        static let disabledControlOpacity: CGFloat = 0.5
        static let captionFontSize: CGFloat = 11
        static let captionOpacity: CGFloat = 0.45
        static let permissionTextMaxWidth: CGFloat = 280
        static let permissionTextMinScale: CGFloat = 0.8

        // Landscape dock on the far right edge
        static let dockSpacing: CGFloat = 10
        static let dockTrailingPadding: CGFloat = 12

        // v5.1 F8 top bar: mode switch left, WB and EV right
        static let screenMargin: CGFloat = 16
        static let topBarTopPadding: CGFloat = 8
        static let modeSegmentSize: CGFloat = 44
        static let modeSwitchPadding: CGFloat = 3
        static let topButtonSize: CGFloat = 44
        static let topButtonSpacing: CGFloat = 8
        static let bottomStackSpacing: CGFloat = 12

        // v5.1 F8 slim stock dial: codes in a glass bar, the full name in a
        // tiny label above. The strip never turns, each code label does.
        static let dialItemWidth: CGFloat = 56
        static let dialHeight: CGFloat = 44
        static let dialCodeFontSize: CGFloat = 12
        static let dialNameFontSize: CGFloat = 10
        static let dialNameOpacity: CGFloat = 0.7
        static let dialUnselectedOpacity: CGFloat = 0.55
        static let dialSelectedFillOpacity: CGFloat = 0.2
        static let dialSelectedInset: CGFloat = 3
        static let dialNameSpacing: CGFloat = 3
        static let dialSnapAnimationDuration: TimeInterval = 0.2

        // v5.1 F8 WB / EV sheets (one open at a time)
        static let sheetPadding: CGFloat = 20
        static let panelSpacing: CGFloat = 12
        static let whiteBalanceSheetHeight: CGFloat = 270
        static let exposureSheetHeight: CGFloat = 150
        static let panelSliderLabelWidth: CGFloat = 52
        static let panelValueWidth: CGFloat = 56
        static let kelvinSliderStep: Double = 50
        static let tintSliderStep: Double = 1
        static let panelAnimationDuration: TimeInterval = 0.2

        // v5: last Roll photo beside the shutter
        static let lastPhotoSize: CGFloat = 44
        static let lastPhotoCornerRadius: CGFloat = 10
        static let lastPhotoBorderWidth: CGFloat = 1
        static let lastPhotoBorderOpacity: CGFloat = 0.6

        // v5.1 F9 Film strip layer: four small slots and glass icons above
        // the dial; Generate takes the Roll thumbnail's place by the shutter
        static let stripSlotSize: CGFloat = 38
        static let stripSlotCornerRadius: CGFloat = 8
        static let stripSlotSpacing: CGFloat = 6
        static let stripEmptySlotOpacity: CGFloat = 0.18
        static let stripCountSpacing: CGFloat = 6
        static let stripCountMaxWidth: CGFloat = 300
        static let stripGenerateSize: CGFloat = 52
        static let stripGenerateIconSize: CGFloat = 20
        static let rollPickerColumns = 3
        static let rollPickerSpacing: CGFloat = 4
        static let rollPickerCornerRadius: CGFloat = 8
    }
}
