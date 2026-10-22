import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Roll contact sheet UI (v5 F6; v5.1 F7; v5.2 S5)
    enum RollUI {
        static let columns = 3
        static let selectionBadgeSize: CGFloat = 24
        static let selectionBadgePadding: CGFloat = Constants.DesignUI.Space.xs
        static let selectionRingWidth: CGFloat = 3
        static let badgeScrimOpacity: CGFloat = 0.45
        // Read by V51AcceptanceTests' 44-pt floor (the system bottom bar now
        // draws the selection actions)
        static let toolbarButtonSize: CGFloat = Constants.DesignUI.targetMin
        // The book badge on photos that have a diary entry (v5.1-6)
        static let diaryBadgeSize: CGFloat = 22
        static let diaryBadgeIconSize: CGFloat = 11
        static let diaryBadgePadding: CGFloat = Constants.DesignUI.Space.xs
    }
}
