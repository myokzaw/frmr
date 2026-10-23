import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Strip screen UI (project.md §2, screen 4; v5.1 F10; v5.2 S3)
    enum StripUI {
        static let swatchDiameter: CGFloat = 34
        static let swatchBorderWidth: CGFloat = 2
        // v4 F8: hairline so a swatch matching the page stays visible
        static let swatchRimWidth: CGFloat = 1
        static let swatchTapTarget: CGFloat = Constants.DesignUI.targetMin
        static let swatchSpacing: CGFloat = Constants.DesignUI.Space.xl
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25

        // Hero strip: fitted between the top glass groups and the sheet's
        // smallest detent, so neither ever covers it
        static let heroTopInset: CGFloat = 64
        static let previewHorizontalPadding: CGFloat = 40
        static let previewSpacing: CGFloat = 20

        // The controls sheet: tool control, tool bar, Keep strip
        static let sheetSmallDetent: CGFloat = 300
        static let sheetPadding: CGFloat = Constants.DesignUI.gutter
        static let sheetSpacing: CGFloat = Constants.DesignUI.Space.s
        // Header (44) + ruler (44) + gap, as in the editor
        static let toolPanelHeight: CGFloat = 104
    }
}
