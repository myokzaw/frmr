# BUG-V4-9 OPEN v4-13 (change an entry's stock after saving) is not marked in code
- Severity: minor | Owner: backend (marker), frontend if it goes in EntryDetailView
- Steps: `grep -rn "v4-13" frmr/` returns nothing. Every other Part 2 open decision (v4-9…v4-12, v4-14…v4-16) has a marker.
- Expected (frmr-v4-spec.md §Definition of done (Part 2): "OPEN markers in place"; §F11 "Changing an entry's stock after saving is not in v4 (OPEN v4-13)"): an `// OPEN: v4-13` at the natural site, for example `DiaryEntry.filmStock` / `filmStockRaw` (Models/DiaryEntry.swift:16-35) or EntryDetailView. Possibly also a decision flag in Constants, as done for v4-4/v4-8 (`stripVignetteEnabled`, `usesColourCube`).
- Related, lower priority: v4-12 (gallery picks take the camera's stock) is marked in PhotoboothViewModel.swift:67 and CameraViewModel, but has no Constants value. That's acceptable, since it's behaviour rather than a number. Listed here only for consistency with the v4-4/v4-8 pattern.
- Same bug class as BUG-V4-1: decisions with no code site lose their marker.
