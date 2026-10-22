import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Roll grid UI (v5 F6; v5.1 F7, F10)
    enum RollUI {
        static let columns = 3
        static let gridSpacing: CGFloat = 3
        static let gridInset: CGFloat = 3
        static let cellCornerRadius: CGFloat = 8
        static let selectionBadgeSize: CGFloat = 24
        static let selectionBadgePadding: CGFloat = 6
        static let selectionRingWidth: CGFloat = 3
        static let selectedDimOpacity: CGFloat = 0.35
        static let toolbarSpacing: CGFloat = 6
        static let toolbarHorizontalPadding: CGFloat = 12
        static let toolbarVerticalPadding: CGFloat = 8
        static let toolbarOuterPadding: CGFloat = 12
        static let toolbarButtonSize: CGFloat = 44
        static let toolbarIconSize: CGFloat = 18
        // The book badge on photos that have a diary entry (v5.1-6)
        static let diaryBadgeSize: CGFloat = 22
        static let diaryBadgeIconSize: CGFloat = 11
        static let diaryBadgePadding: CGFloat = 6
        // Empty state
        static let emptyIconSize: CGFloat = 40
        static let emptySpacing: CGFloat = 12
        static let emptyButtonHeight: CGFloat = 46
        static let emptyButtonHorizontalPadding: CGFloat = 24
    }
}
