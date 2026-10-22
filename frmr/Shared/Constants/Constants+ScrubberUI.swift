import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Effect scrubber, tool icon bar and glass buttons (v5.1 F8/F10)
    enum ScrubberUI {
        // A tick every 5%: VoiceOver adjusts in the same steps
        static let step: Double = 0.05
        // Light haptic every 10%, a stronger one at 100% (v5.1-10)
        static let hapticStep: Double = 0.1
        static let referenceValue: Double = 1
        static let percentScale: Double = 100

        static let rulerHeight: CGFloat = 44
        static let rulerInset: CGFloat = 8
        static let tickWidth: CGFloat = 1.5
        static let minorTickHeight: CGFloat = 10
        static let majorTickHeight: CGFloat = 16
        static let referenceTickHeight: CGFloat = 26
        static let markerWidth: CGFloat = 3
        static let markerHeight: CGFloat = 34
        static let idleTickOpacity: CGFloat = 0.28
        static let activeTickOpacity: CGFloat = 0.85
        static let headerSpacing: CGFloat = 6
        static let resetButtonSize: CGFloat = Constants.DesignUI.targetMin
        static let disabledOpacity: CGFloat = 0.4

        // Tool icon bar
        static let toolItemWidth: CGFloat = 52
        static let toolItemHeight: CGFloat = 52
        static let toolIconSize: CGFloat = 20
        static let toolTitleMinScale: CGFloat = 0.7
        static let toolDotSize: CGFloat = 5
        static let toolIdleOpacity: CGFloat = 0.6

        // Round glass icon buttons
        static let glassButtonSize: CGFloat = Constants.DesignUI.buttonGlass
        static let glassButtonIconSize: CGFloat = 17
    }
}
