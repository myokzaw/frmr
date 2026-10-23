#if DEBUG
import UIKit

// Compiled out of release. Launch arguments that make UI tests faster
// (v5.1 F11). Called once from FrmrApp.init.
enum UITestSupport {
    /// Turns animations off so a UI test never waits for a transition.
    static let fastArgument = "-UITestFast"

    static var isFast: Bool {
        ProcessInfo.processInfo.arguments.contains(fastArgument)
    }

    static func applyLaunchArguments() {
        if isFast {
            // The render debounce shortens itself (Constants.PhotoEdit.renderDebounce).
            UIView.setAnimationsEnabled(false)
        }
    }
}
#endif
