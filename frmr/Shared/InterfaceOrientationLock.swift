import OSLog
import UIKit

// The camera preview's AVCaptureVideoPreviewLayer must never physically
// rotate — if the interface autorotated with the device, the crop and
// composition the user framed would shift under them. CameraView locks the
// interface to portrait while it's on screen (and releases the lock when it
// isn't) so the preview stays put; CameraViewModel's device-orientation
// tracking then counter-rotates just the chrome so buttons and readouts stay
// upright.
//
// UIKit decides the allowed orientations as the intersection of the app-level
// mask (AppDelegate, else Info.plist) and the top full-screen view
// controller's own mask. That answer is cached: changing `mask` alone does
// nothing until the controllers are told to re-ask, and requestGeometryUpdate
// is validated against the cached answer, so the order below matters:
//   1. set mask  2. setNeedsUpdateOfSupportedInterfaceOrientations on every
//   controller  3. requestGeometryUpdate (forces a landscape scene back).
@MainActor
enum InterfaceOrientationLock {
    // nonisolated so the Equatable conformance is usable from pure mappings and tests
    nonisolated enum Mode: Equatable {
        case portraitLocked
        case unlocked
    }

    private static let log = Logger(subsystem: "frmr", category: "orientation")

    private(set) static var mode: Mode = .unlocked
    static var mask: UIInterfaceOrientationMask { mask(for: mode) }

    // No PortraitUpsideDown in either case: the Info.plist omits it on iPhone,
    // so the unlocked mask must too or the intersection would be empty.
    nonisolated static func mask(for mode: Mode) -> UIInterfaceOrientationMask {
        switch mode {
        case .portraitLocked: .portrait
        case .unlocked: .allButUpsideDown
        }
    }

    // Idempotent; call on every appear and on becoming active.
    static func lockToPortrait() { apply(.portraitLocked) }
    static func unlock() { apply(.unlocked) }

    private static func apply(_ newMode: Mode, isRetry: Bool = false) {
        mode = newMode
        guard let scene = activeScene() else {
            log.error("orientation \(String(describing: newMode)): no window scene")
            return
        }
        for window in scene.windows {
            refresh(window.rootViewController)
        }
        let mask = mask(for: newMode)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            // Not surfaced via AppError: a failed lock is not user-actionable
            // (the camera still works, chrome still counter-rotates), so this
            // is a documented silent path; console log only.
            log.error("requestGeometryUpdate(\(mask.rawValue)) failed: \(error.localizedDescription)")
            Task { @MainActor in
                guard !isRetry, mode == newMode else { return }
                // The controllers may not have re-evaluated yet on first try.
                try? await Task.sleep(for: .seconds(Constants.Camera.orientationLockRetryDelay))
                guard mode == newMode else { return }
                apply(newMode, isRetry: true)
            }
        }
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    // Hosting controllers derive their mask from SwiftUI content, so every
    // level of the hierarchy is asked to re-evaluate, not only the root.
    private static func refresh(_ controller: UIViewController?) {
        guard let controller else { return }
        controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        for child in controller.children { refresh(child) }
        refresh(controller.presentedViewController)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { InterfaceOrientationLock.mask }
    }
}
