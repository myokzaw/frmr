import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Strip screen UI (project.md §2, screen 4)
    enum StripUI {
        static let swatchDiameter: CGFloat = 30
        static let swatchBorderWidth: CGFloat = 2
        // v4 F8: hairline so a swatch matching the page stays visible
        static let swatchRimWidth: CGFloat = 1
        static let swatchTapTarget: CGFloat = 44
        static let actionCornerRadius: CGFloat = 10
        static let actionFontSize: CGFloat = 13
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25

        // v4 F7 controls card: rows that appear or disappear with the stock
        // (print, effects) fade rather than jump
        static let controlRowAnimationDuration: TimeInterval = 0.2
        // "Effects" group label inside the card (project.md §2 screen 6 label
        // style); the font is .caption so it scales with Dynamic Type
        static let groupLabelTracking: CGFloat = 0.96   // 0.08em at 12pt
    }
}
