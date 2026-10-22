import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Effect strength sliders (v5 F5)
    enum EffectSliderUI {
        // A tick every 5%: VoiceOver adjusts in the same steps
        static let step: Double = 0.05
        static let percentWidth: CGFloat = 56
        static let titleWidth: CGFloat = 84
        static let titleMinScale: CGFloat = 0.7
        static let rowMinHeight: CGFloat = Constants.DesignUI.targetMin
        static let percentScale: Double = 100
    }
}
