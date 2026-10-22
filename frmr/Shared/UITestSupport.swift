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
            // OPEN: the render debounce (Constants.PhotoEdit.renderDebounce)
            // is backend-owned; shortening it for tests needs a contract
            // request. Animations are the UI-only cost.
            UIView.setAnimationsEnabled(false)
        }
    }
}
#endif
