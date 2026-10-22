import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Photo edit screen UI (v5 F4)
    enum PhotoEditUI {
        static let topBarHeight: CGFloat = 52
        static let topBarSpacing: CGFloat = 8
        static let hintOpacity: CGFloat = 0.6
        static let hintMinScale: CGFloat = 0.7
        static let sectionSpacing: CGFloat = 12
        static let tabHeight: CGFloat = 40
        static let tabUnderlineHeight: CGFloat = 2
        static let toolPanelHeight: CGFloat = 252
        static let actionButtonHeight: CGFloat = 50
        static let rowSpacing: CGFloat = 4
        static let compareBadgePadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.2
        // Hold-to-compare: press forever, the pressing callback does the work
        static let compareMaximumDistance: CGFloat = 60
        static let chipColumnMinimum: CGFloat = 104
    }
}
