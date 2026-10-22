import SwiftUI

// v5.2 M0: the one place the app chooses its floating-control material
// (research §4.5). Glass belongs on the control layer over media only
// (viewfinder, editor photo, strip hero), never on list rows or paper screens.
//
// - iOS 26: Liquid Glass (`.glassEffect`), optionally tinted amber when
//   prominent and touch-reactive when interactive.
// - iOS 17–25: a frosted blur, with a hairline shadow under white glyphs
//   because a thin material over a bright sky is not enough contrast.
// - Reduce Transparency: an opaque surface, either way. Darkroom surfaces get
//   #001219 at 92%; paper surfaces get the theme `surface` role.

private struct GlassBackground<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    let shape: S
    let prominent: Bool
    let interactive: Bool
    let surface: FrmrSurface

    private var opaqueFill: Color {
        surface == .darkroom
            ? Color.appBlack.opacity(Constants.DesignUI.opaqueDarkroomOpacity)
            : ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast).surface
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent && reduceTransparency {
            content.background(Color.appAmber, in: shape)
        } else if reduceTransparency {
            content.background(opaqueFill, in: shape)
        } else if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else if prominent {
            content.background(Color.appAmber, in: shape)
        } else {
            content
                .shadow(
                    color: surface == .darkroom ? .black.opacity(Constants.DesignUI.glyphShadowOpacity) : .clear,
                    radius: 0,
                    x: 0,
                    y: Constants.DesignUI.glyphShadowOffset
                )
                .background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        var glass = Glass.regular
        if prominent { glass = glass.tint(.appAmber) }
        if interactive { glass = glass.interactive() }
        return glass
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
    /// - Parameters:
    ///   - prominent: the screen's one primary action (amber glass on iOS 26, an amber fill before).
    ///   - interactive: touch-reactive glass on iOS 26; ignored before.
    ///   - surface: `.darkroom` for the always-dark camera and editor chrome; `.paper`
    ///     for theme-following screens, whose Reduce Transparency fallback is the theme surface.
    func frmrGlass<S: Shape>(
        in shape: S,
        prominent: Bool = false,
        interactive: Bool = false,
        surface: FrmrSurface = .darkroom
    ) -> some View {
        modifier(GlassBackground(shape: shape, prominent: prominent, interactive: interactive, surface: surface))
    }

    /// Glass in a capsule: the common case for floating chips and bars.
    func frmrGlassCapsule(prominent: Bool = false, interactive: Bool = false) -> some View {
        frmrGlass(in: Capsule(), prominent: prominent, interactive: interactive)
    }

    /// Glass for theme-following screens (viewers, walkthrough bubbles):
    /// the same material, with the paper fallback under Reduce Transparency.
    func frmrAdaptiveGlass<S: Shape>(in shape: S) -> some View {
        frmrGlass(in: shape, surface: .paper)
    }

    func frmrAdaptiveGlassCapsule() -> some View {
        frmrAdaptiveGlass(in: Capsule())
    }

    /// Backing for small sheets: iOS 26 draws its own glass sheet; earlier
    /// systems get the frosted blur; Reduce Transparency gets solid.
    func frmrSheetBackground() -> some View {
        modifier(SheetBackground())
    }

    /// Lets this view's glass morph with another's inside a `FrmrGlassContainer`
    /// (a WB/EV button becoming its sheet). No-op before iOS 26.
    @ViewBuilder
    func frmrGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// The screen's one primary action: amber fill with near-black text
    /// (8.47:1), `.glassProminent` tinted amber on iOS 26. The label should
    /// use `.font(.frmrLabel)`.
    @ViewBuilder
    func frmrPrimaryButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(.appAmber)
                .foregroundStyle(Color.appBlack)
                .frame(minHeight: Constants.DesignUI.buttonPrimaryHeight)
        } else {
            buttonStyle(FrmrAmberCapsuleButtonStyle())
        }
    }
}

/// iOS 17–25 primary button: an amber capsule. Dims on press, and inherits
/// the system's disabled dimming.
struct FrmrAmberCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.frmrLabel)
            .foregroundStyle(Color.appBlack)
            .padding(.horizontal, Constants.DesignUI.Space.xl)
            .frame(minHeight: Constants.DesignUI.buttonPrimaryHeight)
            .background(Color.appAmber, in: Capsule())
            .opacity(configuration.isPressed ? Constants.DesignUI.primaryPressedOpacity : 1)
            .contentShape(Capsule())
    }
}

/// Groups glass shapes so they blend and morph together (iOS 26); a plain
/// group before. One container per function group, never one long bar.
struct FrmrGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            Group { content }
        }
    }
}
