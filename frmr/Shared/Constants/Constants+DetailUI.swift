import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Full-screen detail viewers (entry / strip; v5.1 F10, v5.2 §5.7)
    enum DetailUI {
        static let textSpacing: CGFloat = Constants.DesignUI.Space.m
        static let photoHeightFraction: CGFloat = 0.6
    }
}
