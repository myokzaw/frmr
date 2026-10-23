import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Shared photo action controls (choice chips, Download, Saved)
    enum ReviewUI {
        static let stockChipHeight: CGFloat = Constants.DesignUI.targetMin
        static let stockChipHorizontalPadding: CGFloat = 14
        static let stockChipSpacing: CGFloat = Constants.DesignUI.Space.s
        static let downloadButtonSize: CGFloat = Constants.DesignUI.buttonGlass
        static let savedHorizontalPadding: CGFloat = Constants.DesignUI.Space.m
        static let savedVerticalPadding: CGFloat = 6
    }
}
