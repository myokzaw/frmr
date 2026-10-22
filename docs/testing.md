# Testing frmr

How the tests are laid out, how to run them, and the rule to follow before adding one. Written after the one-off test consolidation (2026-10-21); the before/after lists and the mapping from every removed test to the test that now covers it are in `qa/test-consolidation/`.

---

## 1. The rule: search before you add

Before writing a test:

1. **Grep the theme first.** Search the file for that theme in the table below (and `grep -rn "<thing under test>" frmrTests`) for the type, function or behaviour you are about to test. Search the bodies, not only the names: the same behaviour has often been tested under three different names.
2. **If a test already covers the behaviour, extend it.** Add an argument to the parameterised test (a new effect, stock, surface or orientation is one more argument), or one more assertion to the existing test. Do not add a near-duplicate beside it.
3. **Add a new test only for distinct semantics.** Pure-math unit tests that no workflow test reproduces stay as unit tests. Where a workflow test (a matrix over every stock or orientation) already proves the same thing, keep the stronger one.
4. **Put it in the file for its theme** (section 2). A new file only for a new theme.
5. **Shared helpers live in `frmrTests/TestSupport.swift`** (`PixelBuffer`, `solidImage`, `Raster`, `flatImage`, `ciFlat`, `makeScratchDefaults`). Check there before writing another pixel reader or image builder.

---

## 2. Where each kind of test lives

### Unit tests (`frmrTests/`, Swift Testing)

| File | Theme |
|---|---|
| `TestSupport.swift` | Shared helpers only. No tests. |
| `FilmModelTests.swift` | Pure film maths: curves, print balancing, neutrality, monotonicity, black and white targets, toe, cube shape and cache, colour-matrix rows. |
| `FilmCalibrationTests.swift` | Per-stock character relationships (warmth order, Portrait softer than Daylight, Cine teal shadows, and so on). |
| `FilmEffectsTests.swift` | Halation, grain, haze (bloom) and light-leak behaviour and seeds. |
| `FilmLookTests.swift` | `FilmLook` model and migrations, effect-strength scaling, vignette, strip roll look. |
| `OffIsIdentityTests.swift` | The identity invariants (section 3): strength 0 and stock Off change nothing. |
| `ImageProcessorTests.swift` | `ImageProcessor` strip look, EXIF orientation mapping, full-frame look, `FilmLookCache`, live film preview. |
| `StripLookRegressionTests.swift` (QA) | Strip look across every stock × B&W × effect: orientation oracle, determinism, Off fast path, never-darken. |
| `FilmAtCaptureRegressionTests.swift` (QA) | As shot strips, per-photo stock plumbing, booth paper, `renderFullLook` orientation and seeds, HEIC, Download. |
| `V51AcceptanceTests.swift` (QA) | v5.1 acceptance: accent and destructive colour roles ≥4.5:1 on theme surfaces, text on accent and amber fills, 44pt minimum on interactive size constants, walkthrough copy. |
| `RotationAcceptanceTests.swift` (QA) | Chrome counter-rotation across every start angle and orientation, onboarding portrait gate. |
| `StripGeneratorTests.swift` | Chunking into strips, layout, the plain booth strip, superseded renders. |
| `StripControlsTests.swift` | Strip screen controls and the As shot vs override rules. |
| `FilmStockMigrationTests.swift` | Stored-value migrations (stock, strip background, defaults), the spec tables. |
| `CameraControlTests.swift` | Gesture mappings, white balance list, camera film stock control. |
| `CameraManualControlTests.swift` | Photo mode launch, camera panels, white balance and exposure controls. |
| `RollAndPhotoEditTests.swift` | Roll store, `PhotoEditViewModel`, re-edit, camera edit presentation. |
| `DiaryTests.swift` | Prompts, per-photo stock, diary review state, the entry look seed. |
| `PersistenceTests.swift` | SwiftData round trips for the diary models. |
| `OnboardingTests.swift`, `OnboardingLockModeTests.swift` | Walkthrough sequencing and orientation lock mode, typewriter text. |
| `InterfaceOrientationLockTests.swift`, `PhotoModeViewHelperTests.swift`, `LibraryTabAndHapticTests.swift` | Small single-purpose helpers. |

Files marked (QA) belong to the QA agent; the rest follow the usual owner rules.

### UI tests (`frmrUITests/`, XCTest)

| File | Theme |
|---|---|
| `PhotoModeUITests.swift` | Photo mode chrome and stock dial, the edit step and sliders, the Roll (select, strip, clear, re-edit, delete). Uses `-UITestPhotoEdit` and `-UITestSeedRoll` (DEBUG-only launch arguments). |
| `DiaryReviewUITests.swift` | Diary and Film strip film chip, the review screen (Download, OK, Retake), saved entry in its stock. Uses `-UITestDiaryReview`. |
| `StripScreenUITests.swift` | Strip screen via the photobooth picker, every stock choice, Settings strip defaults. Needs photos in the simulator library. |

There are deliberately no Xcode-template tests (launch and launch-performance): every real UI test launches the app.

### Gated calibration tools (not regression tests)

Skipped unless the environment variables are set. Photos are personal and never go in git.

| Tool | Variables (pass with the `TEST_RUNNER_` prefix) | Output |
|---|---|---|
| `FilmStockSampleSheetTests` | `FRMR_FILM_SAMPLES_DIR` (folder of `.dng`), `FRMR_FILM_SAMPLES_OUT` | One contact sheet per photo, all stocks side by side. |
| `StripSampleRenderTests` | `FRMR_STRIP_SAMPLES_DIR`, `FRMR_STRIP_SAMPLES_OUT` | A booth strip on each paper, As shot with four stocks. |
| `StripRenderTimingTests` | none (always runs) | Render time of a 4 × 12 MP strip; the simulator baseline is about 80 ms warm. |
| UI screenshots | `TEST_RUNNER_SHOTS_DIR=<abs dir>` (and `SHOTS_SUFFIX` for the strip screen) | Screenshots from the UI tests. |

```bash
TEST_RUNNER_FRMR_FILM_SAMPLES_DIR=/path/to/dngs TEST_RUNNER_FRMR_FILM_SAMPLES_OUT=/path/to/out \
xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination 'platform=iOS Simulator,id=37A97720-A320-4FAA-AD16-4CEBE632C793' \
  -parallel-testing-enabled NO -only-testing:frmrTests/FilmStockSampleSheetTests test
```

---

## 3. The parameterised themes and the invariants they guard

These are the places where a new case is an argument, not a new test. Invariant numbers refer to `docs/film-simulation.md` §8.

| Test (file) | Arguments | Guards |
|---|---|---|
| `effectAtZeroStrengthIsPixelIdentical` (`OffIsIdentityTests`) | effect (halation, haze, light leak, vignette, grain) × input (flat mid grey, bright dot on black) | §8.5: strength 0 is pixel-identical to off, for every effect. A new effect: add a case to `Effect`. |
| `vignetteZeroLeavesTheStockLookUnchanged` (`OffIsIdentityTests`) | every stock except Off | §8.5: the vignette defaults to nothing in every stock's full look. |
| `stockOffReturnsTheOriginalInstanceWithoutRendering` (`OffIsIdentityTests`) | surface (full look, film look cache, diary review, photo edit) | §8.5/§8.6: stock Off hands back the original, never a copy, and does not render. The strip look is covered by `offFastPathReturnsTheOriginal` (orientations × effects × prints). A new surface: add a case. |
| `sameSeedIsPixelIdentical` (`StripLookRegressionTests`) | every stock × B&W | §8.7: same seed gives identical pixels; another seed gives a different frame. |
| `stripRenderIsByteIdentical` (`StripLookRegressionTests`) | every stock | §8.7: a strip re-render is byte-identical. |
| `fullLookIsSeedDeterministic` (`FilmAtCaptureRegressionTests`) | every stock except Off × default and boosted strengths | §8.7: `renderFullLook` is seed-deterministic and seed-sensitive. |
| `paperTextureIsDeterministicPerDateAndStrip` (`FilmAtCaptureRegressionTests`) | both paper backgrounds | §8.7: the paper texture follows date and strip index, exists, and is faint. |
| `asShotStripIsDeterministic` (`FilmAtCaptureRegressionTests`) | strip index × both papers | §8.7: As shot strips re-render byte-identically. |
| `rightTaggedMatchesUpright`, `leftTaggedMatchesUpright`, `everyOrientationMatchesUpright`, `redEdgeLandsOnTheCorrectSide`, `fullStripMatchesUprightStrip` (`StripLookRegressionTests`) | every stock (× B&W × 8 effect combinations, or all 8 orientations) | §8.1: a tagged photo comes out upright and the strip look keeps the slot size. |
| `fullLookKeepsOrientation`, `heicKeepsTheOrientationTag` (`FilmAtCaptureRegressionTests`) | every stock except Off × 8 orientations | §8.1: the full-resolution look and HEIC keep sensor pixels, size and orientation tag. |
| `asShotOverOneStockMatchesThatOverrideExactly`, `overrideIgnoresEveryFrameStock` (`FilmAtCaptureRegressionTests`) | a spread of stocks | As shot and override give byte-identical strips (seeds are per global frame index). |
| `bloomAndLeakNeverDarkenAStrip` (`StripLookRegressionTests`) | every stock except Off × B&W | Haze and light leak only brighten. |
| `exifOrientationMapsToTheMatchingUIImageOrientationAndBack` (`ImageProcessorTests`) | the 8 EXIF orientations | §8.1: the EXIF to UIKit mapping, both ways. |
| `storedValuesMigrateToTheirStock` (`FilmStockMigrationTests`) | v2 values, unknown values, every current raw value | Stored stock values never break, and unknown ones read as Off. |
| `diaryEntryRoundTripsItsStock` (`DiaryTests`) | every stock | A diary entry keeps its stock through SwiftData. |
| `colourMatrixRowsSumToOne` (`FilmModelTests`) | every negative | §8.2: a neutral is untouched by the colour matrix. |

The full mapping from every §8 invariant to its guarding tests, including the invariants no unit test can guard, is in `qa/test-consolidation/mapping.md`.

---

## 0. Workflow for parallel agents (read first)

**Use `scripts/test.sh` for every run; don't call `xcodebuild` by hand.** Each role has its own simulator and its own DerivedData, so agents running at the same time never share a device or a build folder.

| Role | Simulator | DerivedData |
|---|---|---|
| lead | `frmr-lead` | `build/lead` |
| backend | `frmr-backend` | `build/backend` (its UI shards: `frmr-ui-4…6`, so it can run alongside the frontend) |
| frontend | `frmr-frontend` | `build/frontend` |
| qa | `frmr-qa` | `qa/DerivedData` |
| restyle (second frontend agent) | `frmr-restyle` | `build/restyle` (its UI shards: `frmr-ui-4…6`) |
| UI shards | `frmr-ui-1`, `frmr-ui-2`, `frmr-ui-3` | the caller's DerivedData |

**Tiers.** Use the cheapest tier that proves the change:

| Command | When | Typical time |
|---|---|---|
| `scripts/test.sh suite <role> <Suite>...` | While iterating: only the themed suites you touched (see §2) | build plus a few seconds |
| `scripts/test.sh suite <role> --no-build <Suite>...` | Re-running after a test-only change, or reading a failure again | about 6 s |
| `scripts/test.sh fast <role>` | Before handing back: every unit test except the slow matrix and timing suites | build plus about 20 s |
| `scripts/test.sh unit <role>` | QA and lead at the end of a round: every unit test | build plus about 40 s |
| `scripts/test.sh ui <role> [Class...]` | Frontend for its own UI classes; QA and lead for all. Sharded across 3 simulators, which seed the photo fixtures themselves | build plus about a third of the serial time |
| `scripts/test.sh all <role>` | Lead's final check before a commit | unit + UI |

**Why it's fast:**
- `build-for-testing` runs once, then every run is `test-without-building`.
- The slow suites (`StripLookRegressionTests`, `FilmAtCaptureRegressionTests`, `StripRenderTimingTests`) are skipped in `fast`.
- UI classes are spread across three simulators that run at the same time. Xcode's own parallel testing stays off (`-parallel-testing-enabled NO`), because cloning simulators fails on this machine; the shards replace it.

**Two agents at once:** frontend uses UI shards 1–3 and backend uses 4–6. Don't run `frmr-guard --all` or extra builds while UI shards are running; heavy load causes flaky UI timeouts.

**The script fails on:** a build error, any failing test, or any Swift warning. Logs go to `build/test-logs/`.

**Creating the simulators** (once per machine): `xcrun simctl create frmr-backend "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-4`, and the same for the other names in the table.

**Parallel rounds:** when backend and frontend work at the same time, the lead may give each agent its own git worktree. They then can't see each other's half-finished edits, and the lead merges them. Ownership rules still apply, so the merges stay conflict-free.

## 4. How to run

Run serially. Parallel simulator clones fail on this machine. Give each run its own derived-data folder (`qa/DerivedData`) so it does not collide with an implementer's build.

```bash
cd "/Users/johnzaw/Desktop/projects/Frmr app /frmr"

# Guard (constraints from CLAUDE.md); about a minute
./scripts/frmr-guard.sh --all

# Unit tests
xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination 'platform=iOS Simulator,id=37A97720-A320-4FAA-AD16-4CEBE632C793' \
  -derivedDataPath qa/DerivedData -parallel-testing-enabled NO -only-testing:frmrTests test
```

Expect `Test run with N tests in M suites passed` and no `.swift:…: warning` lines. (`qa/DerivedData` prints many "Stale file … outside the allowed root paths" build-system warnings; they are not Swift warnings.) Swift Testing counts a parameterised test once however many arguments it has; the log's `Test case passing …` lines show each argument.

```bash
# UI tests (a different simulator)
UDID=1B3A9DB6-1D5A-4447-9849-CF49C94A5FC8
xcrun simctl addmedia $UDID qa/fixtures/strip-fixture-*.png      # StripScreenUITests needs 4+ photos
xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath qa/DerivedData -parallel-testing-enabled NO -only-testing:frmrUITests test
```

The Roll, diary and strip records the UI tests need are created by the tests themselves through the DEBUG-only launch arguments (`-UITestSeedRoll`, `-UITestPhotoEdit`, `-UITestDiaryReview`); only the photo-library fixtures need seeding by hand, once per simulator. Keep the simulator in portrait.

List the tests (for before/after comparisons) after a `build-for-testing` or `test` run:

```bash
qa/test-consolidation/list-tests.sh frmrTests out.txt     # suite/test ids and the count
python3 -I qa/test-consolidation/cases.py <xcodebuild-log> # argument cases of parameterised tests
```

The simulator has no camera, orientation sensor or haptics: what only a device can show stays on the device checklist in the QA reports.
