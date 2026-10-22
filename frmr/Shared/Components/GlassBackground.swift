import SwiftUI

// v5.1 F8/F10: the one place the app chooses its floating-control material.
// Liquid Glass on iOS 26; a frosted blur on iOS 17–25, so every screen keeps
// the same layout whatever the system version. With Reduce Transparency on,
// both become an opaque dark fill (v5.1 audit).
private struct GlassBackground<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.appBlack.opacity(Constants.CameraUI.opaqueGlassOpacity), in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct SheetBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.presentationBackground(Color.appBlack)
        } else if #available(iOS 26, *) {
            content
        } else {
            content.presentationBackground(.ultraThinMaterial)
        }
    }
}

extension View {
    /// Backs the view with the app's glass material in `shape`.
    func frmrGlass<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    /// Glass in a capsule: the common case for floating chips and bars.
    func frmrGlassCapsule() -> some View {
        frmrGlass(in: Capsule())
    }

    /// Backing for small sheets: iOS 26 draws its own glass sheet; earlier
    /// systems get the frosted blur; Reduce Transparency gets solid.
    func frmrSheetBackground() -> some View {
        modifier(SheetBackground())
    }
}
