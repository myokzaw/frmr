import UIKit

// The three physical moments in the app (v2 F8a). Generators are held rather
// than made on demand: `prepare()` warms the Taptic Engine, and a cold
// generator adds enough latency that the tap stops feeling connected to the
// shutter.
//
// If the user has haptics off at the system level these silently no-op, which
// is why there's no setting here.
@MainActor
enum Haptics {
    private static let shutter = UIImpactFeedbackGenerator(style: .heavy)
    private static let focus = UIImpactFeedbackGenerator(style: .light)
    private static let notification = UINotificationFeedbackGenerator()

    /// Call on the path leading up to a capture or a render, not at the moment itself.
    static func prepareShutter() { shutter.prepare() }
    static func prepareStripComplete() { notification.prepare() }

    static func shutterFired() { shutter.impactOccurred() }
    static func focusLocked() { focus.impactOccurred() }
    static func stripCompleted() { notification.notificationOccurred(.success) }
}
