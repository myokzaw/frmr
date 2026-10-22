import SwiftUI

// v5.1 F8/F10: colour roles with separate light and dark values, so text and
// icons keep at least 4.5:1 (3:1 for large text and icons) on their surface.
// Measured against the theme backgrounds and cards (project.md §5):
//   accent       light 8A4300 on cream 5.2, on card 6.0 | dark amber on black 8.5, on card 6.9
//   destructive  light 8F2D00 on cream 5.8, on card 6.8 | dark E8704A on black 6.2, on card 5.1
// The palette's own amber, orange and rust fail on one of the two themes
// (orange on cream 2.7, rust on dark card 2.8), hence the extra values.
extension ThemePalette {
    private static let accentLight = Color(hex: "8A4300")
    private static let destructiveLight = Color(hex: "8F2D00")
    private static let destructiveDark = Color(hex: "E8704A")

    /// The one accent: selection, links, the primary action.
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .appAmber : accentLight
    }

    /// Text or icon on a filled accent surface.
    static func onAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .appBlack : .white
    }

    /// Delete and Clear rows and icons (the rust role).
    static func destructive(for scheme: ColorScheme) -> Color {
        scheme == .dark ? destructiveDark : destructiveLight
    }
}

// Glass for theme-following screens (Library, Settings, viewers, walkthrough).
// `frmrGlass(in:)` already falls back to an opaque *dark* fill under Reduce
// Transparency, which suits the always-dark camera chrome; these screens
// follow light/dark, so their fallback is the system surface instead.
private struct AdaptiveGlass<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
        } else {
            content.frmrGlass(in: shape)
        }
    }
}

extension View {
    func frmrAdaptiveGlass<S: Shape>(in shape: S) -> some View {
        modifier(AdaptiveGlass(shape: shape))
    }

    func frmrAdaptiveGlassCapsule() -> some View {
        frmrAdaptiveGlass(in: Capsule())
    }

    /// Bottom content inset so lists end above the floating tab bar, and a
    /// soft edge under it on iOS 26.
    @ViewBuilder
    func frmrTabBarScrollInsets() -> some View {
        if #available(iOS 26, *) {
            contentMargins(.bottom, Constants.LibraryUI.bottomContentInset, for: .scrollContent)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            contentMargins(.bottom, Constants.LibraryUI.bottomContentInset, for: .scrollContent)
        }
    }
}
