import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Entry editor UI (project.md §2, screen 2; v5.1 F10)
    enum EditorUI {
        static let photoHeightFraction: CGFloat = 0.42
        static let promptFontSize: CGFloat = 25
        static let entryFontSize: CGFloat = 16
        static let charCountFontSize: CGFloat = 12
        static let cardCornerRadius: CGFloat = 20
        static let buttonCornerRadius: CGFloat = 16
        static let buttonPadding: CGFloat = 16
        static let entryMinHeight: CGFloat = 120
        static let linkFontSize: CGFloat = 14
        static let linkSpacing: CGFloat = 28
        // v5.1 F10: the photo header runs full bleed under rounded bottom corners
        static let headerCornerRadius: CGFloat = 28
        static let primaryButtonHeight: CGFloat = 52
        static let skipButtonHeight: CGFloat = 44
        static let formSpacing: CGFloat = 16
    }
}
