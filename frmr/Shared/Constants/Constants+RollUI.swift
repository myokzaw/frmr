import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Roll grid UI (v5 F6)
    enum RollUI {
        static let columns = 3
        static let gridSpacing: CGFloat = 2
        static let selectionBadgeSize: CGFloat = 24
        static let selectionBadgePadding: CGFloat = 6
        static let selectionRingWidth: CGFloat = 3
        static let selectedDimOpacity: CGFloat = 0.35
        static let toolbarSpacing: CGFloat = 16
        static let emptyIconSize: CGFloat = 40
        static let emptySpacing: CGFloat = 12
        static let emptyButtonCornerRadius: CGFloat = 10
        static let emptyButtonHeight: CGFloat = 46
        static let emptyButtonHorizontalPadding: CGFloat = 24
    }
}
