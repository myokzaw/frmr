import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Diary review screen (v4 F10/F13)
    enum ReviewUI {
        static let stockChipHeight: CGFloat = 44
        static let stockChipHorizontalPadding: CGFloat = 14
        static let stockChipFontSize: CGFloat = 13
        static let stockChipSpacing: CGFloat = 8
        static let downloadButtonSize: CGFloat = 44
        static let downloadIconSize: CGFloat = 17
        static let savedFontSize: CGFloat = 13
        static let savedHorizontalPadding: CGFloat = 12
        static let savedVerticalPadding: CGFloat = 6
        static let overlayOpacity: CGFloat = 0.45
        static let actionButtonHeight: CGFloat = 50
        static let sectionSpacing: CGFloat = 16
        static let effectsMaxHeight: CGFloat = 230
        static let feedbackAnimationDuration: TimeInterval = 0.2
    }
}
