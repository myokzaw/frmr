import CoreHaptics
import UIKit

/// The physical moments in the app (v2 F8a, v5.2 S7).
nonisolated enum HapticEvent: CaseIterable, Sendable {
    /// A light tick: a notch of a scrubber or dial, a focus lock.
    case detent
    /// A firmer tick at a reference value (0 EV).
    case reference
    /// The shutter plus the lever winding on (film advance).
    case shutterAdvance
    /// Something was saved or finished.
    case saved
    /// Something needs attention.
    case warning
}

/// What a `HapticEvent` becomes: pure, so the mapping is testable without a
/// Taptic Engine.
nonisolated enum HapticFeedback: Equatable, Sendable {
    enum Impact: Equatable, Sendable { case light, medium, heavy, rigid }
    enum Notification: Equatable, Sendable { case success, warning }

    case impact(Impact)
    case notification(Notification)
    /// The Core Haptics film-advance pattern.
    case filmAdvance

    /// - Parameters:
    ///   - filmAdvanceEnabled: `Constants.DefaultsKeys.filmAdvanceHaptics`.
    ///   - coreHapticsAvailable: whether this device can play a custom
    ///     pattern; without it the shutter is a heavy impact.
    static func feedback(
        for event: HapticEvent, filmAdvanceEnabled: Bool, coreHapticsAvailable: Bool
    ) -> HapticFeedback {
        switch event {
        case .detent: return .impact(.light)
        case .reference: return .impact(.rigid)
        case .shutterAdvance:
            return filmAdvanceEnabled && coreHapticsAvailable ? .filmAdvance : .impact(.heavy)
        case .saved: return .notification(.success)
        case .warning: return .notification(.warning)
        }
    }
}

// Generators are held rather than made on demand: `prepare()` warms the
// Taptic Engine, and a cold generator adds enough latency that the tap stops
// feeling connected to the shutter.
//
// If the user has haptics off at the system level these silently no-op. The
// one setting here is the film-advance pattern (default on).
@MainActor
enum Haptics {
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static var engine: CHHapticEngine?

    /// Reads the film-advance setting; on unless the user turned it off.
    nonisolated static func isFilmAdvanceEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Constants.DefaultsKeys.filmAdvanceHaptics) as? Bool ?? true
    }

    static var supportsCoreHaptics: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    /// Call on the path leading up to a capture or a render, not at the moment itself.
    static func prepareShutter() {
        heavy.prepare()
        if isFilmAdvanceEnabled(), supportsCoreHaptics { startEngineIfNeeded() }
    }
    static func prepareStripComplete() { notification.prepare() }

    static func play(_ event: HapticEvent, defaults: UserDefaults = .standard) {
        let feedback = HapticFeedback.feedback(
            for: event, filmAdvanceEnabled: isFilmAdvanceEnabled(in: defaults), coreHapticsAvailable: supportsCoreHaptics
        )
        switch feedback {
        case .impact(.light): light.impactOccurred()
        case .impact(.medium): medium.impactOccurred()
        case .impact(.heavy): heavy.impactOccurred()
        case .impact(.rigid): rigid.impactOccurred()
        case .notification(.success): notification.notificationOccurred(.success)
        case .notification(.warning): notification.notificationOccurred(.warning)
        case .filmAdvance:
            if !playFilmAdvance() { heavy.impactOccurred() }
        }
    }

    // MARK: Core Haptics

    private static func startEngineIfNeeded() {
        guard engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            created.isAutoShutdownEnabled = true
            // The engine stops after a spell of inactivity or an audio
            // interruption; the next play restarts it
            created.stoppedHandler = { _ in Task { @MainActor in engine = nil } }
            created.resetHandler = { Task { @MainActor in engine = nil } }
            try created.start()
            engine = created
        } catch {
            print("[Haptics] Core Haptics engine unavailable: \(error)")
            engine = nil
        }
    }

    /// Plays the shutter + winding pattern; false when it couldn't, so the
    /// caller falls back to a heavy impact.
    private static func playFilmAdvance() -> Bool {
        startEngineIfNeeded()
        guard let engine else { return false }
        typealias C = Constants.Haptics
        func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: time
            )
        }
        var events = [transient(0, intensity: C.shutterIntensity, sharpness: C.shutterSharpness)]
        for (index, intensity) in C.advanceTickIntensities.enumerated() {
            let time = C.advanceStartDelay + C.advanceTickSpacing * Double(index)
            events.append(transient(time, intensity: intensity, sharpness: C.advanceTickSharpness))
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            print("[Haptics] Film-advance pattern failed: \(error)")
            return false
        }
    }
}
