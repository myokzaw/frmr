import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Entry editor UI (project.md §2, screen 2)
    enum EditorUI {
        static let photoHeightFraction: CGFloat = 0.38
        static let promptFontSize: CGFloat = 25
        static let entryFontSize: CGFloat = 16
        static let charCountFontSize: CGFloat = 12
        static let cardCornerRadius: CGFloat = 12
        static let buttonCornerRadius: CGFloat = 10
        static let buttonPadding: CGFloat = 16
        static let entryMinHeight: CGFloat = 120
        static let linkFontSize: CGFloat = 14
        static let linkSpacing: CGFloat = 28
    }
}
