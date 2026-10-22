import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Photo edit screen UI (v5 F4, v5.1 F2/F3/F8)
    enum PhotoEditUI {
        static let topBarSpacing: CGFloat = 8
        static let topBarPadding: CGFloat = 12
        static let hintOpacity: CGFloat = 0.6
        static let hintMinScale: CGFloat = 0.7
        static let sectionSpacing: CGFloat = 8
        // Header (44) + ruler (44) + gap, so switching tools never moves the photo
        static let toolPanelHeight: CGFloat = 104
        static let actionButtonHeight: CGFloat = 52
        static let actionButtonCornerRadius: CGFloat = 16
        static let actionSpacing: CGFloat = 12
        static let compareBadgePadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.2
        // Hold-to-compare: press forever, the pressing callback does the work
        static let compareMaximumDistance: CGFloat = 60
        static let chipSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 16
    }
}
