import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Strip screen UI (project.md §2, screen 4; v5.1 F10; v5.2 S3)
    enum StripUI {
        static let swatchTapTarget: CGFloat = Constants.DesignUI.targetMin
        // v4 F8: hairline so a swatch matching the page stays visible
        static let swatchRimWidth: CGFloat = 1
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25

        // Hero strip: fitted under the top glass groups, above the controls
        static let heroTopInset: CGFloat = 64
        static let previewHorizontalPadding: CGFloat = 40
        static let previewSpacing: CGFloat = 20

        // The controls under the hero, as in the editor
        static let sheetPadding: CGFloat = Constants.DesignUI.gutter
        static let sheetSpacing: CGFloat = Constants.DesignUI.Space.s
        // Header (44) + ruler (44) + gap, as in the editor
        static let toolPanelHeight: CGFloat = 104
        static let topBarPadding: CGFloat = Constants.DesignUI.Space.m
        // Paper swatches are the editor's preview thumbs
        static let paperSpacing: CGFloat = Constants.DesignUI.Space.s
        // Preview thumbs share the editor's size
        static let previewThumbWidth: CGFloat = Constants.PhotoEditUI.previewWidth
        static let previewThumbHeight: CGFloat = Constants.PhotoEditUI.previewHeight
        static let asShotCode = "AS"
    }
}
