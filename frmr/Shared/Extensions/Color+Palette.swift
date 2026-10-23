import SwiftUI

// nonisolated: immutable palette values, readable from the render pipeline
nonisolated extension Color {
    // Hex is a compile-time constant from the design palette, so a malformed
    // string is a programmer error; the initializer falls back to black.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    static let appBlack = Color(hex: "001219")
    static let appTealDark = Color(hex: "005F73")
    static let appTeal = Color(hex: "0A9396")
    static let appTealLight = Color(hex: "94D2BD")
    static let appCream = Color(hex: "E9D8A6")
    static let appAmber = Color(hex: "EE9B00")
    static let appOrange = Color(hex: "CA6702")
    static let appRust = Color(hex: "BB3E03")
    static let appRed = Color(hex: "AE2012")
    static let appCrimson = Color(hex: "9B2226")

    // Card surfaces from project.md §5 theme tables
    static let appCardLight = Color(hex: "F5E9C6")
    static let appCardDark = Color(hex: "062830")

    // Role-specific shades. The palette's own rust and red fail 4.5:1 as text
    // on at least one surface, so destructive text uses these instead
    // (measured values are in the ThemePalette comment below).
    static let appRustDeep = Color(hex: "8F2D00")
    static let appRustDeeper = Color(hex: "6E2200")
    static let appCoral = Color(hex: "E8704A")
    static let appCoralLight = Color(hex: "FF8F6B")
    static let appSystemRed = Color(hex: "FF453A")
    static let appSystemRedLight = Color(hex: "FF6B61")
    static let appTealDeeper = Color(hex: "00404D")
    static let appMint = Color(hex: "B8E6D4")
}

// Which family of roles a screen draws from (research/v5.2-ui-makeover.md §4.1).
// Darkroom: capture and editing, always dark. Paper: writing and browsing,
// following the system appearance.
nonisolated enum FrmrSurface: Equatable {
    case darkroom
    case paper
}

// The one place colour roles live (v5.2 §4.4; absorbs the v5.1 accent roles).
// Pure: `resolve` takes the scheme, surface and contrast, so views read the
// three environment values and call it once outside their body, and tests
// can sweep every combination. Increase Contrast = `.increased`.
//
// Measured contrast, standard / increased (text on bg, surface):
//   text       darkroom 19.1 | paper light 13.5 | paper dark 13.5 (max already)
//   textMuted  alpha 0.65/0.65/0.70 (>= 5.2) -> 0.85/0.85/0.90 (>= 9.1)
//   tint       darkroom + dark 11.1 | light 5.14 -> 8.06
//   destructive darkroom 4.6 | light 5.8 | dark 5.1  -> all >= 5.6
//   onAccent   #001219 on amber 8.47 in every surface
// Rules: amber is a fill, never text and never a thin line on cream (1.59:1);
// mid-teal #0A9396 is never a fill behind white text (3.73:1).
nonisolated struct ThemePalette {
    let bg: Color
    let surface: Color
    let text: Color
    let textMuted: Color
    /// Shutter, primary button, selection fill. Always amber.
    let accentFill: Color
    /// Text or glyph on `accentFill`.
    let onAccent: Color
    /// Links, toggles, tab selection, text-level selection.
    let tint: Color
    let destructive: Color
    /// The 3-pt bar or dot that marks the selected item.
    let selectedIndicator: Color
    let cardBorder: Color

    // Names from before v5.2, kept so existing call sites read the same.
    var background: Color { bg }
    var card: Color { surface }
    var muted: Color { textMuted }

    /// The viewfinder letterbox: pure black, not the darkroom `bg`.
    static let letterbox = Color.black

    static func resolve(
        for scheme: ColorScheme,
        surface: FrmrSurface = .paper,
        contrast: ColorSchemeContrast = .standard
    ) -> ThemePalette {
        let increased = contrast == .increased
        if surface == .darkroom {
            return darkroom(increased: increased)
        }
        return scheme == .dark ? paperDark(increased: increased) : paperLight(increased: increased)
    }

    private static func darkroom(increased: Bool) -> ThemePalette {
        ThemePalette(
            bg: .appBlack,
            surface: Color.white.opacity(0.08),
            text: .white,
            textMuted: Color.white.opacity(increased ? 0.85 : 0.65),
            accentFill: .appAmber,
            onAccent: .appBlack,
            tint: .appTealLight,
            destructive: increased ? .appSystemRedLight : .appSystemRed,
            selectedIndicator: .appAmber,
            cardBorder: Color.white.opacity(increased ? 0.4 : 0.15)
        )
    }

    private static func paperLight(increased: Bool) -> ThemePalette {
        ThemePalette(
            bg: .appCream,
            surface: .appCardLight,
            text: .appBlack,
            textMuted: Color.appBlack.opacity(increased ? 0.85 : 0.65),
            accentFill: .appAmber,
            onAccent: .appBlack,
            tint: increased ? .appTealDeeper : .appTealDark,
            destructive: increased ? .appRustDeeper : .appRustDeep,
            selectedIndicator: increased ? .appTealDeeper : .appTealDark,
            cardBorder: Color.appBlack.opacity(increased ? 0.4 : 0.12)
        )
    }

    private static func paperDark(increased: Bool) -> ThemePalette {
        ThemePalette(
            bg: .appBlack,
            surface: .appCardDark,
            text: .appCream,
            textMuted: Color.appCream.opacity(increased ? 0.9 : 0.7),
            accentFill: .appAmber,
            onAccent: .appBlack,
            tint: increased ? .appMint : .appTealLight,
            destructive: increased ? .appCoralLight : .appCoral,
            selectedIndicator: increased ? .appMint : .appTealLight,
            cardBorder: Color.appTealLight.opacity(increased ? 0.6 : 0.25)
        )
    }
}
