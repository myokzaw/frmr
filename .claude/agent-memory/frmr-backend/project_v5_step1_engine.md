---
name: v5-step1-engine
description: v5 step 1 backend decisions — FilmLook/strengths, Roll, PhotoEditViewModel, WB/EV API, shared render scheduler
metadata:
  type: project
---

- FilmLook (Models/FilmLook.swift): stock, printStock (not `print`, avoids shadowing), blackAndWhite, Strengths(halation, haze, lightLeak, grain, vignette). Tolerant Codable: Bool = on(1)/off(0), `bloom` key = haze, `effects` key = strengths, clamps to 0...1.5 (Strength.sliderMaximum, OPEN v5-6).
- StripCustomization stores `strengths`; `effects` is a Bool facade (FilmEffects) kept ONLY so QA's StripLook/FilmAtCapture regression tests compile unchanged. Don't remove until QA edits them.
- Pipeline: every effect stage is skipped at strength 0 (identical to off); applyBloom/applyLightLeak got `strength:` params (default 1); grain = stock.grainIntensity * strength; new applyVignette (multiply radial gradient after the cube, stock != none only).
- UserDefaults: strengths stored as Doubles under the old keys (stripHalation, stripLightLeak) + new stripHaze/stripGrain/stripVignette; stripBloom read once as haze fallback. NSNumber.doubleValue reads old Bools correctly.
- FilmLookScheduler (Features/Camera/FilmLookRenderScheduler.swift) is shared by DiaryReviewViewModel and PhotoEditViewModel: JPEG->RAW watch + generation-based last-wins render; ImageProcessor.fullResolutionHEIC(of:look:seed:) shared by both Downloads and Roll export.
- DiaryEntry.lookData (Data?, additive) stores a look only when != stock defaults; FilmLookCache keys on (id, FilmLook, size).
- RollPhoto @Model (id, capturedAt, photoPath "Roll/<uuid>.jpg", lookData Data, editedAt); RollViewModel statics insert/update/delete/clearRoll + instance export/selection. PhotoEditViewModel serves capture and re-edit (init?(editing:)).
- Swift Testing gotchas: `#require(Type(arg, closure))` with a non-@Sendable closure param warns — build the @Sendable closure into a local first. CameraViewModel in tests works without a camera (session calls are queue no-ops).
- Panels: CameraViewModel.openPanel (film/whiteBalance/exposure); isFilmStockExpanded/isWhiteBalanceExpanded are now computed. selectWhiteBalance(_:) closes; chooseWhiteBalancePreset(_:) keeps the panel (Photo panel).
- Tests: 218 -> 305 (FilmLookTests, RollAndPhotoEditTests, CameraManualControlTests).
