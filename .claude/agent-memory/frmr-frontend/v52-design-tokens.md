---
name: v5.2 design tokens
description: where the M0 tokens live and the traps met landing them
type: project
---
- Tokens: Shared/Design/{FrmrType,FrmrMotion}.swift, Constants/Constants+DesignUI.swift, ThemePalette roles in Extensions/Color+Palette.swift, glass in Components/GlassBackground.swift. ThemePalette+Accent.swift is gone.
- `ThemePalette.resolve(for:surface:contrast:)` is pure; views read colorScheme + colorSchemeContrast and call it once. Test sweeps it in ThemeRoleContrastTests (V51AcceptanceTests.swift).
- `frmrGlass` default surface is .darkroom (camera/editor); paper screens use frmrAdaptiveGlass or `surface: .paper`.
- UI tests `testStripScreenCyclesEveryStock` and `testSaveToRollThenReEditAndDelete` failed once while frmr-guard --all built concurrently, passed on rerun: do not run the guard in parallel with UI tests.
