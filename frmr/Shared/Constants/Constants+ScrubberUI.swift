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
        static let resetIconSize: CGFloat = 16
        // Exposure ruler: taller ticks at whole stops
        static let exposureMajorStep: Double = 1
        static let disabledOpacity: CGFloat = 0.4

        // Tool icon bar; each glyph sits in its value ring (v5.2 M5)
        static let toolItemWidth: CGFloat = 56
        static let toolItemHeight: CGFloat = Constants.DesignUI.targetMin + Constants.DesignUI.Space.l
        static let toolIconSize: CGFloat = 17
        static let toolIdleOpacity: CGFloat = 0.65
        static let toolRingDiameter: CGFloat = 32
        static let toolRingWidth: CGFloat = 2
        static let toolRingTrackOpacity: CGFloat = 0.2
        // The ring starts at 12 o'clock
        static let toolRingStartDegrees: Double = -90

        // Round glass icon buttons
        static let glassButtonSize: CGFloat = Constants.DesignUI.buttonGlass
        static let glassButtonIconSize: CGFloat = 17
    }
}
