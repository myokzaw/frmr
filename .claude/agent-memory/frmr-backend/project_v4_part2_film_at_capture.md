---
name: v4-part2-film-at-capture
description: v4 Part 2 (ex-v5) F8/F11/F12 model decisions — plain strip, per-photo stock, As shot = nil filmStock
metadata:
  type: project
---

- Spec v5 was folded into frmr-v4-spec.md "Part 2": F8 plain strip, F9 camera stock/live preview, F10 diary review, F11 per-photo stock, F12 As shot. OPEN v4-9…v4-14 (old v5-1…6).
- F12: kept `StripCustomization.filmStock` name, now `FilmStock?` (nil = As shot) so StripView's Picker (iOS 17 tag includeOptional) and QA's `customization.filmStock = stock` compile. Per-frame resolution via `effective(forFrameStock:)`; applyStripLook treats nil as Off.
- Gotcha: `customization.filmStock = .none` now means nil (Optional.none) + compiler warning; write `FilmStock.none`.
- Settings stock default: key absent = As shot; sentinel `Constants.Strip.asShotStoredValue` ("asShot"); stored v4 stocks stay overrides; legacy grain key only if present.
- QA StripLookRegressionTests.describe uses `c.filmStock.rawValue`; a test-target-only Optional<FilmStock>.rawValue shim at the end of frmrTests.swift keeps it compiling (remove when QA updates).
- F8: StripBackground is now just white, black (CaseIterable); .cream/.custom deleted after frontend removed usages. Stored "cream"/unknown → white. paperBorder renamed outerMargin; `drawsPaperBorder=false` (OPEN v4-9). Background "cream" is rewritten to "white" in migrateLegacyDefaults.
- F11: DiaryEntry.filmStockRaw String? (unversioned schema → automatic lightweight migration). PhotoboothShot struct; StripItem/Cell have filmStock with default .none.
- Step 2 (F9/F10/F11 display/F13): CameraViewModel.filmStock (private(set), selectFilmStock, persisted DefaultsKeys.cameraFilmStock, init(defaults:)); captureForPhotobooth returns PhotoboothShot (PhotoboothViewModel.add(_ shot:) overload keeps CameraView compiling); gallery picks default to CameraViewModel.storedFilmStock(in: .standard).
- Review: DiaryReviewViewModel (Features/Diary) owned by CameraViewModel.review; pendingDiaryImage/Stock/DisplayImage computed from it; Constants.Diary.presentsReviewStep=false keeps old capture→editor flow until frontend's review view lands.
- ImageProcessor.renderFullLook(of:stock:seed:coveringPixelSize:) throws: sensor-space, keeps orientation tag, Off returns same instance; filmLook() shared with applyStripLook. heicData works on simulator. Sim timing 12MP: full look 0.6-0.85 s, HEIC 0.15-0.19 s, screen-size 0.15 s.
- FilmLookCache (NSCache, cost-limited) + DiaryViewModel.displayImage(for:size:scale:) async / cachedDisplayImage.
- Live preview: FilmPreviewRenderer.swift (frame sink, MTKView delegate, FilmPreviewView). Tap conversion stays on the existing preview layer underneath (decision). CIRenderDestination.isFlipped = true verified upright by an offscreen Metal texture test on the sim. Data output connection: angle 90 + front mirroring set once per connection (also after switchCamera); disabled when stock Off.
- F15 booth strip: StripGenerator.Layout is internal (photoRect/captionRect/dateRect); Constants.Strip border 6, frameGap 4, cellAspectRatio 0.8, frameCornerRadius 2.5, boothCaptionLines 1 (captionMaxLines 2 still used by frontend FilmStripCell), paperWhite/paperBlack RGB + paperTexture (seeded, cell grid drawn scaled). outerMargin/contentPadding/cellSpacing removed. Gated tool frmrTests/StripSampleRenderTests (FRMR_STRIP_SAMPLES_DIR/OUT).
