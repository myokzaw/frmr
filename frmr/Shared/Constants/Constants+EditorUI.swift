import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Prompt / entry screen UI (project.md §2, screen 2; v5.2 S4)
    enum EditorUI {
        static let formSpacing: CGFloat = Constants.DesignUI.Space.l
        // The 4:5 photo header takes about 40% of a tall phone
        static let photoMaxHeight: CGFloat = 340
        // While typing the photo shrinks to a thumbnail beside the prompt
        static let thumbnailSize: CGFloat = 64
        static let entryMinHeight: CGFloat = 120
        // The placeholder sits where TextEditor draws its first line
        static let placeholderInset: CGFloat = 8
        static let placeholderLeadingInset: CGFloat = 5
        // The count turns destructive in the last this-many characters
        static let charCountWarningRemaining = 20
        // Read by V51AcceptanceTests' 44-pt floor
        static let skipButtonHeight: CGFloat = Constants.DesignUI.targetMin
    }
}
