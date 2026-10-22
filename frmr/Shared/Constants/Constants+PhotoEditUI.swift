import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Photo edit screen UI (v5 F4, v5.1 F2/F3/F8, v5.2 M5)
    enum PhotoEditUI {
        static let topBarSpacing: CGFloat = Constants.DesignUI.Space.s
        static let topBarPadding: CGFloat = Constants.DesignUI.Space.m
        static let hintOpacity: CGFloat = 0.7
        static let sectionSpacing: CGFloat = Constants.DesignUI.Space.s
        // Header (44) + ruler (44) + gap, so switching tools never moves the photo
        static let toolPanelHeight: CGFloat = 104
        static let actionSpacing: CGFloat = Constants.DesignUI.Space.m
        static let compareBadgePadding: CGFloat = Constants.DesignUI.Space.s
        // Hold-to-compare: press forever, the pressing callback does the work
        static let compareMaximumDistance: CGFloat = 60
        static let horizontalPadding: CGFloat = Constants.DesignUI.gutter

        // v5.2 M5: Film and Print as rows of this photo in each choice, 4:5
        static let previewWidth: CGFloat = 56
        static let previewHeight: CGFloat = 70
        static let previewSpacing: CGFloat = Constants.DesignUI.Space.s
        static let previewRingWidth: CGFloat = 2
        static let previewLabelSpacing: CGFloat = Constants.DesignUI.Space.xs

        // v5.2 C2: the JPEG preview looks "latent" until the RAW develops
        static let latentSaturation: Double = 0.55
        static let latentContrast: Double = 0.85
        static let latentBlur: CGFloat = 1.5
    }
}
