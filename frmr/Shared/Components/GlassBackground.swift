import SwiftUI

// v5.1 F8/F10: the one place the app chooses its floating-control material.
// Liquid Glass on iOS 26; a frosted blur on iOS 17–25, so every screen keeps
// the same layout whatever the system version.
extension View {
    /// Backs the view with the app's glass material in `shape`.
    @ViewBuilder
    func frmrGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// Glass in a capsule: the common case for floating chips and bars.
    func frmrGlassCapsule() -> some View {
        frmrGlass(in: Capsule())
    }
}
