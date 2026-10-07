import Observation
import SwiftData
import SwiftUI
import UIKit

// Drives the first-run walkthrough (v3 F5/F6).
//
// The walkthrough is the one thing in the app that appears without a tap —
// a deliberate, bounded exception recorded in frmr-v3-spec.md §F5. It shows
// only when all three gates hold: permission resolved, portrait, not yet
// completed. Rotation mid-walkthrough hides the overlay but keeps the step,
// so the user resumes where they were when the phone comes back upright.
@Observable
final class OnboardingViewModel {
    // Current coach mark; nil when the walkthrough isn't running
    private(set) var step: CoachStep?
    private(set) var hasCompleted = false
    // Set by CameraView once the system camera-permission dialog has been
    // answered (either way) — the walkthrough must never sit behind it
    private(set) var isPermissionResolved = false
    // Portrait gate only — the walkthrough never enters the counter-rotation system
    private(set) var isPortrait = true

    // Bindable so the Settings replay row can return the user to the camera
    var selectedTab: AppTab = .camera

    var errorState: ErrorState?

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var orientationObserver: NSObjectProtocol?

    // What the overlay actually shows: the walkthrough hides in landscape
    // without losing its place
    var visibleStep: CoachStep? {
        isPortrait ? step : nil
    }

    static func shouldPresent(
        hasCompleted: Bool,
        permissionResolved: Bool,
        isPortrait: Bool
    ) -> Bool {
        !hasCompleted && permissionResolved && isPortrait
    }

    // Face-up/down/unknown hold the last known state
    static func isPortrait(for orientation: UIDeviceOrientation, current: Bool) -> Bool {
        switch orientation {
        case .portrait, .portraitUpsideDown: return true
        case .landscapeLeft, .landscapeRight: return false
        default: return current
        }
    }

    // Only the camera tab needs the portrait lock (its preview must not
    // rotate); every other tab follows the device. Exhaustive on purpose so a
    // new tab forces a decision here.
    nonisolated static func lockMode(for tab: AppTab) -> InterfaceOrientationLock.Mode {
        switch tab {
        case .camera: .portraitLocked
        case .library, .settings: .unlocked
        }
    }

    // MARK: Stepping

    func advance() {
        guard let step else { return }
        if let next = step.next {
            self.step = next
        } else {
            complete()
        }
    }

    func skip() {
        guard step != nil else { return }
        complete()
    }

    // Replay is a full reset, not a resume — always starts at .library
    func reset() {
        hasCompleted = false
        step = .library
        persist()
    }

    private func complete() {
        step = nil
        guard !hasCompleted else { return }
        hasCompleted = true
        persist()
    }

    private func presentIfNeeded() {
        guard step == nil,
              Self.shouldPresent(
                  hasCompleted: hasCompleted,
                  permissionResolved: isPermissionResolved,
                  isPortrait: isPortrait
              )
        else { return }
        step = .library
    }

    // MARK: Gates

    // Called by CameraView after CaptureSession.ensurePermission returns —
    // the suspension point guarantees the system dialog has been answered
    func notePermissionResolved() {
        isPermissionResolved = true
        presentIfNeeded()
    }

    // Settings → "Show intro again". If the device is in landscape the same
    // portrait gate applies: the walkthrough appears on rotation upright.
    // OPEN: v3-3 — the row copy doesn't surface the portrait requirement
    func replayWalkthrough() {
        reset()
        selectedTab = .camera
    }

    // MARK: Lifecycle

    func start(context: ModelContext) {
        modelContext = context
        load()
        startObservingOrientation()
    }

    private func load() {
        guard let modelContext else { return }
        do {
            let state = try modelContext.fetch(FetchDescriptor<OnboardingState>()).first
            hasCompleted = state?.hasCompletedWalkthrough ?? false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
        }
    }

    private func persist() {
        guard let modelContext else { return }
        do {
            let state = try modelContext.fetch(FetchDescriptor<OnboardingState>()).first
                ?? {
                    let created = OnboardingState()
                    modelContext.insert(created)
                    return created
                }()
            state.hasCompletedWalkthrough = hasCompleted
            try modelContext.save()
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
        }
    }

    // Same observer pattern as CameraViewModel, but this one lives for the
    // whole app session — the walkthrough overlays every tab, so it can't
    // borrow the camera's observer, which stops when that tab disappears.
    private func startObservingOrientation() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyOrientation(UIDevice.current.orientation)
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyOrientation(UIDevice.current.orientation)
        }
    }

    private func applyOrientation(_ orientation: UIDeviceOrientation) {
        isPortrait = Self.isPortrait(for: orientation, current: isPortrait)
        // Landscape at first launch shows nothing and completes nothing; the
        // walkthrough appears the first time the phone is held upright
        presentIfNeeded()
    }
}
