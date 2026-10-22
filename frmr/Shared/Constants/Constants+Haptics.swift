import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Haptics (v5.2 S7)
    enum Haptics {
        /// The film-advance pattern (research §6.1): one sharp transient (the
        /// shutter), then soft, decreasing transients as the lever winds on.
        static let shutterIntensity: Float = 1
        static let shutterSharpness: Float = 1
        /// Delay of the first winding tick after the shutter, in seconds
        static let advanceStartDelay: TimeInterval = 0.12
        /// Gap between the winding ticks
        static let advanceTickSpacing: TimeInterval = 0.04
        /// Intensity of each winding tick, strongest first
        static let advanceTickIntensities: [Float] = [0.5, 0.35, 0.2]
        static let advanceTickSharpness: Float = 0.3
    }
}

nonisolated extension Constants.Camera {
    // MARK: Chrome placement (v5.2 S1)

    /// The viewfinder is 3:4 (width : height = 3 : 4) in portrait.
    static let viewfinderAspectHeightOverWidth: CGFloat = 4.0 / 3.0
    /// Height the stock dial and the shutter stack need under the
    /// viewfinder for `.below` placement (dial row + gap + shutter + gap).
    static let belowChromeStackHeight: CGFloat = 172
    /// Minimum breathing room above the viewfinder (status bar / chips),
    /// on top of the top safe area.
    static let belowChromeTopMargin: CGFloat = 8
}
