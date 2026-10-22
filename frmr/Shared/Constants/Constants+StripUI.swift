import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Strip screen UI (project.md §2, screen 4; v5.1 F10)
    enum StripUI {
        static let swatchDiameter: CGFloat = 34
        static let swatchBorderWidth: CGFloat = 2
        // v4 F8: hairline so a swatch matching the page stays visible
        static let swatchRimWidth: CGFloat = 1
        static let swatchTapTarget: CGFloat = 44
        static let swatchSpacing: CGFloat = 16
        // Still read by StripDetailView (restyle agent's file)
        static let actionFontSize: CGFloat = 13
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25

        // Hero strip: nearly the whole space above the glass sheet
        static let previewHeightFraction: CGFloat = 0.96
        static let previewHorizontalPadding: CGFloat = 40
        static let previewSpacing: CGFloat = 20
        static let closeButtonPadding: CGFloat = 12

        // Glass bottom sheet: tools on top, then Archive / Share / Save
        static let sheetCornerRadius: CGFloat = 28
        static let sheetPadding: CGFloat = 16
        static let sheetSpacing: CGFloat = 8
        // Header (44) + ruler (44) + gap, as in the editor
        static let toolPanelHeight: CGFloat = 104
        static let actionSpacing: CGFloat = 12
        static let saveButtonHeight: CGFloat = 50
        static let saveButtonCornerRadius: CGFloat = 16
        static let iconFillOpacity: CGFloat = 0.1
        static let controlRowAnimationDuration: TimeInterval = 0.2
    }
}
