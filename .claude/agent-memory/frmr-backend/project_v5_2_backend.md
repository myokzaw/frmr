---
name: v5.2 backend
description: Exposure in the cube, previews, swatches, haptics, chrome placement, edit-after-shot (v5.2 round 1)
type: project
---
- Exposure gain is baked INTO the film cube (`FilmChain.exposureGain`, cube cache key includes it, `lutCacheLimit` 16) so highlights hit the shoulder; the cube is still indexed by the unexposed picture (no clamp at lattice edge). White/black normalisation stays solved at 0 EV. Halation: key reads `input*gain`, glow is divided by gain. Stock Off: `applyLinearGain` (plain). `FilmLook.exposure` snapped via `snappedExposure`; `StripCustomization.exposure` carries it to the pipeline (per photo only).
- `FilmLook.altersPhoto` includes exposure != 0; `applyStripLook` guard too.
- Previews: `FilmPreviewThumbnails` (pure) + `PhotoEditViewModel.requestPreviews`; two caches (stock row keyed on look-with-stock-.none, print row keyed on look-with-print-nil) so picking a stock re-renders only prints.
- `captureForPhoto(context:)` — when editAfterEachShot is false AND a context is passed it saves straight to the Roll (`saveStraightToRoll`); frontend must pass `modelContext`.
- Haptics: `HapticFeedback.feedback(for:filmAdvanceEnabled:coreHapticsAvailable:)` is the pure mapping; Core Haptics engine lazily created, stoppedHandler nils it.
- Build gotcha: if the frontend breaks the build mid-run, the .app is left unsigned and the sim says "Launchd job spawn failed" — a clean successful rebuild re-signs. Nested `#require(Raster(try #require(..)))` is a macro recursion error. Heterogeneous tuple `arguments:` can time out the type checker: use a private struct.
