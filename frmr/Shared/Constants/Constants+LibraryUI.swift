import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Library UI (project.md §2, screen 5; v5.1 F10)
    enum LibraryUI {
        static let thumbnailSize: CGFloat = 64
        static let thumbnailCornerRadius: CGFloat = 12
        static let rowSpacing: CGFloat = 14
        static let rowVerticalPadding: CGFloat = 10
        static let listHorizontalPadding: CGFloat = 16
        static let sectionTopSpacing: CGFloat = 20
        static let excerptLineLimit = 3
        static let stripThumbnailHeight: CGFloat = 260
        static let stripColumns = 2
        static let stripColumnSpacing: CGFloat = 16
        // Lists end this far above the floating tab bar
        static let bottomContentInset: CGFloat = 16
        static let stripCornerRadius: CGFloat = 10
        static let stripRowSpacing: CGFloat = 28
        // The glass segmented control above the Library's content
        static let segmentHeight: CGFloat = 40
        static let segmentPadding: CGFloat = 4
        static let segmentSelectedOpacity: CGFloat = 0.22
        static let segmentedTopPadding: CGFloat = 4
        static let segmentedBottomPadding: CGFloat = 10
        static let segmentedAnimationDuration: TimeInterval = 0.2
        // Empty states
        static let emptyIconSize: CGFloat = 36
        static let emptySpacing: CGFloat = 10
    }
}
