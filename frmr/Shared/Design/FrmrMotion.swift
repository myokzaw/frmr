import SwiftUI

// v5.2 M0: motion tokens (research §4.7), each with its Reduce Motion
// fallback. Views never pick a curve themselves: they say which token and
// let `frmrAnimation` read `accessibilityReduceMotion`.
nonisolated enum FrmrMotion: CaseIterable {
    /// Dial detent, toggles.
    case snap
    /// Sheet or panel morph; crossfade under Reduce Motion.
    case panel
    /// The develop ramp while a RAW is pending; instant under Reduce Motion.
    case develop

    typealias M = Constants.DesignUI.Motion

    /// The animation for this token, or nil where Reduce Motion means "just change".
    func animation(reduceMotion: Bool) -> Animation? {
        switch (self, reduceMotion) {
        case (.snap, false): return .spring(duration: M.snapDuration, bounce: M.snapBounce)
        case (.snap, true): return .easeOut(duration: M.snapReducedDuration)
        case (.panel, false): return .spring(duration: M.panelDuration, bounce: M.panelBounce)
        case (.panel, true): return .easeInOut(duration: M.panelReducedDuration)
        case (.develop, false): return .easeOut(duration: M.developDuration)
        case (.develop, true): return nil
        }
    }

    /// HUD flash timing is the same with or without Reduce Motion; only the
    /// scale pulse goes (`hudScale`).
    static func hudScale(reduceMotion: Bool, active: CGFloat, resting: CGFloat) -> CGFloat {
        reduceMotion ? resting : active
    }
}

private struct FrmrAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: FrmrMotion
    let value: V

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.animation(_:value:)` with a design-token curve and its Reduce Motion fallback.
    func frmrAnimation<V: Equatable>(_ motion: FrmrMotion, value: V) -> some View {
        modifier(FrmrAnimation(motion: motion, value: value))
    }
}
