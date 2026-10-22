---
name: v5.2 makeover lessons
description: what the v5.2 screen round changed (camera placement, mini-strip, TipKit, Library picker) and the traps met
type: project
---
- TipKit `#Rule` on events needs a LITERAL count (`$0.donations.count >= 2`); a constant fails the macro. Tips configure in ContentView `.task` (FrmrTips.configure), not AppEntry. UI tests: any `-UITest*` arg hides tips; `-UITestShowTips` shows all. `Tips.resetDatastore()` only works before configure, so "Show tips again" sets a flag read on next launch.
- Walkthrough overlay is gone: ContentView owns `selectedTab`; children switch tabs via `@Environment(\.selectAppTab)`. OnboardingViewModel only supplies the pure `lockMode(for:)` (contract: move it).
- Library tabs are a system segmented Picker in the principal toolbar slot; XCUITest reaches segments as `app.segmentedControls.buttons["Roll"]` (identifiers on segment Text don't surface).
- Film strip slots/gallery/Pick from Roll/Undo/Generate live in `StripSlotsSheet` behind `strip.miniStrip`; Generate dismisses the sheet first and opens the strip cover in the sheet's onDismiss (a cover can't present while the sheet is up).
- Strip screen controls are a non-dismissable system sheet over the cover; Close/Keep dismiss the sheet first, then the cover in onDismiss.
- Camera `.below` placement: viewfinder 3:4 at full width, top bar floats over its top; computed from GeometryReader size + safe-area insets (bottom inset includes the tab bar).
- V52ScreenshotTour (SHOTS_DIR + SHOTS_PREFIX) shoots every screen light/dark/AX5 and skips missing controls, so it serves before and after.
- Constants still read only by QA's V51AcceptanceTests 44-pt sweep were kept (EffectSliderUI.rowMinHeight, ReviewUI.*, RollUI.toolbarButtonSize, LibraryUI.segmentHeight, EditorUI.skipButtonHeight, CameraUI.secondaryButtonSize).
