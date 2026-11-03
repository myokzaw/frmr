import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Crop tool UI (F-122-F)
    enum CropUI {
        /// Hit area of every handle: the 44-pt floor.
        static let handleHitSize: CGFloat = Constants.DesignUI.targetMin
        /// Corner bracket arm length and thickness
        static let cornerLength: CGFloat = 22
        static let cornerThickness: CGFloat = 3
        /// Edge handle bar length and thickness
        static let edgeLength: CGFloat = 28
        static let edgeThickness: CGFloat = 3
        static let frameLineWidth: CGFloat = 1
        static let gridLineWidth: CGFloat = 0.5
        static let gridLineOpacity: Double = 0.7
        /// How dark the part of the photo outside the frame is
        static let dimOpacity: Double = 0.6
        /// Room around the photo while cropping, so edge handles stay inside the view
        static let canvasInset: CGFloat = handleHitSize / 2
        /// Clear space above the photo for the floating top bar
        static let topBarClearance: CGFloat = Constants.DesignUI.targetMin + 2 * Constants.PhotoEditUI.topBarPadding
        static let disabledOpacity: Double = 0.4
        static let chipSpacing: CGFloat = Constants.DesignUI.Space.s
        static let chipHorizontalPadding: CGFloat = Constants.DesignUI.Space.m
        /// Thirds per side of the rule-of-thirds overlay
        static let gridDivisions = 3
    }
}
