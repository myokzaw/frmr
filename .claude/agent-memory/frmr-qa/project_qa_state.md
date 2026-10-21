---
name: qa-state
description: Recurring QA findings and device-only items for frmr camera rotation work
metadata:
  type: project
---
- Angle (SwiftUI) stores radians: compare degrees with tolerance, never ==.
- Bug class: modifier order with .position + rotationEffect (pivot = parent centre). Check on every rotatingWithDevice use.
- UI test runner (frmrUITests) DOES launch and pass on simulator id 1B3A9DB6 (2026-10-06).
- Git baseline is the template; can't diff tests against HEAD.
- Device-only: rotation sign, capture upright, CaptureSession [weak self] capture, haptics.

## v4 QA pass (2026-10-20)
- Unit tests: run with `-parallel-testing-enabled NO` and `-derivedDataPath qa/DerivedData`; read Swift Testing's "Test run with N tests" line. Baseline 127 → 136 with my StripLookRegressionTests (3 suites, ~12 s).
- qa/DerivedData prints ~294 "Stale file ... outside the allowed root paths" build-system warnings (DerivedData made when the project lived at projects/frmr). Not Swift warnings; grep `\.swift:N:N: warning` instead. Deleting qa/DerivedData would clear them.
- Orientation oracle that works: UIKit-drawn upright copy of the tagged image → same applyStripLook → max diff ≤ 2. Exception: the Off fast path through StripGenerator (UIKit draws rotated+scaled in one step) shifts edges ~1 px (max diff 49 at edges) → use mean diff there. Verified by eye, not a bug.
- frmrUITests runner works for QA on 1B3A9DB6 (6 template tests pass), but no test reaches StripView (needs photo seeding). Strip screen still never seen running.
- Recurring bug class: silent `?? input` fallbacks in CI effect chains (no log). OPEN markers missing for decisions with no code site (v4-4, v4-8).
- Device-only v4: capture both landscapes through every stock; per-stock look calibration (v4-5); halation/grain/leak at real slot scale; render timing on device (cold/warm); strip-screen controls.

## v4 Part 2 QA pass (2026-10-20)
- My files: StripLookRegressionTests.swift (9 tests), FilmAtCaptureRegressionTests.swift (17 tests: As shot, per-photo round trip, booth paper, renderFullLook, Download). Suite 215 tests / 41 suites.
- `filmStock` is now `FilmStock?` (nil = As shot). Use `StripCustomization.label(forStockChoice:)` for labels.
- renderFullLook works in SENSOR space and keeps the tag, so grain/leak pattern differs from an upright-input render. Don't use the pixel-exact oracle there; compare the layout via quadrants/bands of a UIKit-upright copy. Horizontal-band tests are meaningless for landscape (.up/.down) images.
- Swift Testing: nested `#require(... #require(...))` fails to compile (recursive macro expansion). Use a helper that returns an optional.
- frmr-guard --all now takes about 60 s (bash loops). Run it in the background.
- UI tests: `xcrun simctl addmedia <udid> qa/fixtures/strip-fixture-*.png` first. DiaryReviewUITests use the DEBUG `-UITestDiaryReview` fixture (CameraView.swift:434-466, inside #if DEBUG).
- Recurring bug class confirmed: OPEN items with no code site lose their marker (v4-4, v4-8, then v4-13).
- The scratchpad is shared with other agents (dng/, sheets*/ hold the user's personal renders). Never copy anything from it into the repo.
