import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Effect strength rows (v5 F5). v5.2 replaced the slider rows with
    // the tick scrubber everywhere; the row height stays for
    // V51AcceptanceTests' 44-pt floor.
    enum EffectSliderUI {
        static let rowMinHeight: CGFloat = Constants.DesignUI.targetMin
    }
}
