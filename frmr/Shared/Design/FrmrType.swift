import SwiftUI

// v5.2 M0: the type scale (research §4.2). Every token is built on a text
// style, so it scales with Dynamic Type.
//
// Serif is the system serif (New York, `design: .serif`) permanently
// (v5.2-8): it has full Dynamic Type, needs no bundling, and is already what
// ships. This closes the old "Newsreader not bundled" OPEN.
//
// Camera chrome rule: glyph-only buttons keep a fixed size and add
// `.frmrLargeContent(_:systemImage:)` so a long-press shows the enlarged
// label; text inside chrome is capped with `.frmrChromeTypeSize()`. Every
// other screen scales fully.
extension Font {
    /// Library and Settings inline titles.
    nonisolated static var frmrTitle: Font { .title2.weight(.semibold) }
    /// The prompt on the writing screen and in the viewer.
    nonisolated static var frmrPrompt: Font { .system(.title3, design: .serif).italic() }
    /// Entry text and empty-state titles.
    nonisolated static var frmrReading: Font { .system(.body, design: .serif) }
    /// Buttons, tool names, list rows.
    nonisolated static var frmrLabel: Font { .subheadline.weight(.medium) }
    /// Dates, counts, hints.
    nonisolated static var frmrMeta: Font { .footnote }
    /// Percentages, Kelvin, EV: digits stay put as they change.
    nonisolated static var frmrValue: Font { .subheadline.monospacedDigit().weight(.semibold) }
    /// Stock codes and edge print. Pair with `.tracking(Constants.DesignUI.codeTracking)`
    /// or use `.frmrCodeStyle()`, which applies both.
    nonisolated static var frmrCode: Font { .system(.caption, design: .monospaced).weight(.semibold) }
    /// Large transient value flash in the viewfinder.
    nonisolated static var frmrHUD: Font { .title.monospacedDigit().weight(.semibold) }
}

extension View {
    /// `.frmrCode` with its tracking, which a `Font` cannot carry.
    func frmrCodeStyle() -> some View {
        font(.frmrCode).tracking(Constants.DesignUI.codeTracking)
    }

    /// Caps Dynamic Type for text inside camera chrome, where room is fixed.
    func frmrChromeTypeSize() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// For fixed-size, glyph-only buttons: long-press shows the enlarged
    /// label at accessibility sizes (Apple's pattern for bars).
    func frmrLargeContent(_ title: LocalizedStringKey, systemImage: String) -> some View {
        accessibilityShowsLargeContentViewer {
            Label(title, systemImage: systemImage)
        }
    }
}
