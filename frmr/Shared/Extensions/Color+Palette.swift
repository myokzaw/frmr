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
}

// Resolved theme colors for the current color scheme (project.md §5).
// Views resolve this once outside their body; no branching inside bodies.
struct ThemePalette {
    let background: Color
    let text: Color
    let primary: Color
    let card: Color
    let cardBorder: Color
    let muted: Color

    static func resolve(for scheme: ColorScheme) -> ThemePalette {
        switch scheme {
        case .dark:
            return ThemePalette(
                background: .appBlack,
                text: .appCream,
                primary: .appTeal,
                card: .appCardDark,
                cardBorder: Color.appTealLight.opacity(0.25),
                muted: Color.appCream.opacity(0.6)
            )
        default:
            return ThemePalette(
                background: .appCream,
                text: .appBlack,
                primary: .appTealDark,
                card: .appCardLight,
                cardBorder: Color.appBlack.opacity(0.12),
                muted: Color.appBlack.opacity(0.6)
            )
        }
    }
}
