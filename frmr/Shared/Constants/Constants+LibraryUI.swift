import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Library UI (project.md §2, screen 5; v5.1 F10; v5.2 M6)
    enum LibraryUI {
        // Entries: the user's words lead, two lines, beside a 4:5 thumbnail
        static let thumbnailWidth: CGFloat = 56
        static let excerptLineLimit = 2
        // Strips: two columns, each strip at the column width
        static let stripColumns = 2
        static let stripColumnSpacing: CGFloat = Constants.DesignUI.Space.l
        static let stripRowSpacing: CGFloat = Constants.DesignUI.Space.xl
        // Lists end this far above the floating tab bar
        static let bottomContentInset: CGFloat = Constants.DesignUI.Space.l
        // Read by V51AcceptanceTests' 44-pt floor (the system segmented
        // control replaced the custom one)
        static let segmentHeight: CGFloat = Constants.DesignUI.targetMin
    }
}
