import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Full-screen detail viewers (entry photo / strip; v5.1 F10)
    enum DetailUI {
        static let topBarButtonSize: CGFloat = 44
        static let topBarIconSize: CGFloat = 16
        static let topBarPadding: CGFloat = 16
        static let footerCornerRadius: CGFloat = 28
        static let footerPadding: CGFloat = 20
        static let footerSpacing: CGFloat = 8
        static let footerOuterPadding: CGFloat = 12
        static let textPanelMaxHeight: CGFloat = 220
        static let promptOpacity: CGFloat = 0.6
        static let metaOpacity: CGFloat = 0.5
        static let photoCornerRadius: CGFloat = 20
        static let photoInset: CGFloat = 8
        static let stripInset: CGFloat = 72
    }
}
