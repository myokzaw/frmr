# BUG-V51-01 Strip screen: amber icons, ruler and borders on cream fail contrast in light mode

- Severity: major (accessibility; audit item "amber primaries / accent roles")
- Owner: frontend
- Spec: v5.2 research §2.1 ("amber must never be text or a thin indicator on cream"); v5.1 F10 colour roles (`ThemePalette.accent(for:)`)
- Steps: light appearance, make a strip (Library > Strips > open one, or Make today's strip). Look at the glass sheet.
- Expected: selected tool, modified dot, scrubber marker, swatch ring and toggle tint use `ThemePalette.accent(for: colorScheme)` (8A4300 on cream, 5.2:1).
- Actual: `StripView.swift` lines 113, 121, 148, 196, 225 pass `.appAmber` (EE9B00) on the cream glass sheet, about 1.6:1. "Paper" and "Halation" labels and icons, the ruler marker and the swatch ring are barely visible.
- Evidence: qa/screenshots/v5.1/qa/light/strip-screen-paper.png, strip-screen-halation.png
- Failing test: none; the colour is chosen inside the view body and cannot be reached from a unit test. Fix suggestion: use the accent role when `colorScheme == .light`; amber stays correct as a fill with dark text (Save button is fine, 8.47:1). `V51ContrastTests` guards the role values.

# Minor, same screen
The glass sheet stops above the bottom safe area; a darker cream band shows under it (light-strip-screen-paper.png, bottom 80 px). Owner: frontend.
