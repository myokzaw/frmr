# frmr — 1.2.2 plan (draft)

**Date:** 2026-10-27
**Status:** In progress (2026-10-27). Step 1 (camera fixes) is done and confirmed on device; step 2 started.
**Version:** app version (`MARKETING_VERSION`) 1.2.1 → **1.2.2**. The home-screen name stays **Frmrr**.
**Branch:** `v1.2.2`, made from `main` @ `90795e0` when work starts.
**Agent rule:** **one Sonnet agent** for this release, working one step at a time (the user asked for this on 2026-10-27, instead of the usual two per round). The lead checks each step, runs the `all` test tier and writes the docs.

## Scope

| ID | What | Kind |
|---|---|---|
| BUG-122-01 | Orientation glitch for a moment when flipping front/back | Bug |
| BUG-122-02 | Viewfinder freezes when flipping; replace with a blur-and-flip transition | Bug |
| F-122-A | Lighter shadows with real blacks (film model v2) | Look |
| F-122-B | Film model versioning: old photos keep their look | Engine |
| F-122-C | Shadows and Highlights tools in the photo editor | Feature |
| F-122-D | "Frmrr" in all visible text | Polish |
| F-122-E | Import from gallery (Library → Roll) | Feature |
| F-122-F | Crop tool for every photo | Feature |

## Decisions made by the user (2026-10-27)

| Question | Decision |
|---|---|
| What kind of camera lag | **Freeze on flip** only. The viewfinder is otherwise fine. |
| How flipping should look | **Blur and flip**, like the iOS Camera |
| How much lighter the shadows should be | **Open shadows, real blacks:** much more shadow detail, with the deepest black only slightly lifted (like a good Portra scan) |
| Which stocks | **Each stock by its character:** Portrait the most open; Slide and Cine 500T the deepest, but less crushed than now |
| Existing Roll photos | **Keep their old look**, through versioning (F-122-B) |
| Re-editing an old photo | **Moves it to the new model when opened in the editor** |
| Old Roll photos in a new strip | Keep their old look |
| Prints | **Lift every print and keep the order** (Matte the most lifted, Projection the deepest), **and add Shadows and Highlights tools now** |
| Shadows and Highlights | **Photo editor only.** They work like Exposure: −100…+100, with 0 = the stock's own look |
| How to approve the new look | A **before/after sheet** that the user approves before it ships |
| Rename | **Visible text only**: code, project, bundle ID and file names stay `frmr` |
| Where gallery import lives | **Library → Roll** only |
| How many to import | **Several at once, edited one by one** |
| Starting look for an import | **Off** |
| Photo shape | **Add a crop step, available for every photo** |
| Crop options | **Aspect presets** (no rotate, straighten or flip) |
| Where the crop shows | **Roll, viewer, entries and export.** Strips use the full photo. |
| Import date | **When imported** |
| Extra import behaviour | **"Imported" badge, develop from RAW when the photo has one, remove location data** |
| Continue to diary on imports | **Yes**, the same as any Roll photo |

---

## BUG-122-01 — Orientation glitch when flipping cameras

**What the user sees:** for about a second after tapping flip, the viewfinder is sideways and/or mirrored wrong, then it corrects itself.

**Likely cause:** `CaptureSession.switchCamera(to:lens:)` swaps the input and calls `commitConfiguration()`, and only afterwards calls `configureVideoConnection()`. The new input creates a new `AVCaptureVideoDataOutput` connection, which starts in sensor orientation (landscape, not mirrored). Those frames reach `FilmPreviewFrameSink` until the portrait angle and front mirroring are set.

**Fix:**
- Set the video connection's rotation angle and mirroring **between `beginConfiguration()` and `commitConfiguration()`**, after the new input is added, so the first frame from the new camera is already correct.
- Clear the frame sink's newest frame when the switch starts, so a frame from the old camera never shows on the new one.
- Check the photo output's connection too. Mirroring and the capture angle for the first shot after a flip must be correct.

**Acceptance:**
- Flip 20 times in a row, with stock Off and with each film stock: no sideways or wrongly mirrored frame shows.
- The first photo after a flip, on both cameras, is upright, and a front-camera shot is mirrored the same way as today.
- `RotationAcceptanceTests` and `InterfaceOrientationLockTests` still pass. Add a test that the connection is configured before commit, using whatever the session wrapper allows us to test.

**Files:** `Features/Camera/CaptureSession.swift`, `Features/Camera/FilmPreviewRenderer.swift` (frame sink reset).

## BUG-122-02 — Freeze on flip → blur-and-flip transition

**What the user sees:** the live preview stalls or stutters while the input switches (a few hundred ms).

**Change:**
- On a flip tap, take the last rendered preview frame, blur it, and play a horizontal 3D flip on the viewfinder (like the iOS Camera).
- Keep the blurred frame on screen until the **first correctly configured frame from the new camera** arrives, then fade the live preview back in.
- **Reduce Motion:** a plain cross-fade through the blurred frame, with no 3D flip.
- **Fast taps:** while a switch is in progress, further flip taps are ignored. The flip button stays enabled to look at, so it doesn't flicker.
- **Failure:** if the new camera can't be attached, the old one stays and the blur clears. A timeout (constant, ~1.5 s) guarantees the blur never sticks.
- The lens selector and the WB/EV overlays don't jump during the transition.

**Acceptance:**
- No frozen or stuttering frame shows without the blur over it.
- The blur always clears, including when the switch fails and after a timeout.
- Fast taps can't leave the camera on the wrong side.
- Reduce Motion gives the cross-fade.
- The flip haptic, if there is one, fires once per real flip.

**Files:** `CameraViewModel.swift` (switch state, first-frame signal), `CameraView.swift` / `CameraChrome.swift` (transition), `CaptureSession.swift` (completion callback for the switch), `Constants+CameraUI.swift` (durations, blur radius, timeout).

---

## F-122-A — Lighter shadows with real blacks (film model v2)

**Why:** in v4 the blacks were pushed down to fix a "grey, milky" look (`research/v4-film-reference-calibration.md`). The current values overshoot: shadows and blacks are too dark on every stock.

**Today's levers:**
- **Print black targets** (sRGB/255): Lab 6, Cinema 4, Projection 3, Matte 28 (`Constants+ImageProcessing.swift`, `Print`).
- **Shadow toe:** `shadowToePivot` 0.18 and `shadowToeExponent` 8. The steep exponent hands deep shadows over to the film's full contrast just below mid grey.
- **Each stock's negative curve:** `dMin`, range, `gamma`, `x0`.

**Targets** (starting points; the final numbers come from the before/after sheet):

| Print | Black now | Black v2 (starting point) |
|---|---|---|
| Projection | 3 | ~10 |
| Cinema | 4 | ~12 |
| Lab | 6 | ~14 |
| Matte | 28 | ~34 (still the most lifted) |

| Stock | Shadow character in v2 |
|---|---|
| Portrait 400 | The most open: soft toe, much shadow detail, gentle black |
| Daylight 200 | Moderately open, still punchy |
| Mono 400 | Moderately open, true-looking blacks |
| Mono 3200 | Deep, but with separation; the grain stays |
| Cine 500T | Deep with a teal shadow cast, less crushed |
| Slide 100 | The deepest of all, less crushed |

**How:**
- Version-2 values live next to the current values (see F-122-B). Nothing in v1 changes.
- Soften the toe through a v2 exponent and/or a lower pivot. Add a per-stock toe strength if one shared toe can't give the ranking above.
- Keep the ordering rules as tests:
  - for each print, the black is lighter in v2 than in v1;
  - the print order holds (Projection darkest … Matte lightest);
  - the stock order holds (Slide deepest … Portrait most open).
- Guard against "milky" blacks: for each stock on its default print, input black stays below a ceiling (constant, ~18/255 except Matte), and output stays monotonic.

**Before/after sheet (gate, stops for user approval):**
- Test photos: a dark interior, a backlit portrait, a night street with practical lights, an overcast landscape, a low-key B&W subject, and a grey ramp.
- Each one runs through every stock on its default print, plus each print on one stock: v1 next to v2.
- Rendered offscreen with the existing sample-sheet test (`FilmStockSampleSheetTests`) and saved as PNGs for the user to review on their phone.
- **Nothing in F-122-A ships until the user approves the sheet.** Feedback can go round more than once.

**Acceptance:**
- The user approves the sheet.
- The ordering and guard tests pass.
- `FilmCalibrationTests`, `FilmModelTests` and `OffIsIdentityTests` pass (Off is unaffected).
- The live viewfinder uses v2.
- `docs/film-simulation.md` is updated with the v2 numbers and why they changed.

## F-122-B — Film model versioning

**Goal:** photos taken before 1.2.2 look exactly as they did, until the user opens one in the editor.

**Design:**
- Add `FilmLook.modelVersion: Int`.
  - A stored look **without the key** decodes as **1**, which covers everything taken before 1.2.2.
  - New looks are created at **2** (the constant `Constants.ImageProcessing.Film.currentModelVersion`).
- The pipeline picks the curves, prints, toe and black targets by `modelVersion`. Film cubes are cached by stock + print + version.
- **The editor upgrades:** opening a v1 photo in the photo editor sets the edited look to v2, so the editor shows the new look. Saving stores v2. Discarding leaves the stored look at v1.
- **Everything else keeps the stored version:** Roll, viewer, entries, Download/export, and new strips built from old Roll photos.
- Strips already saved as images don't change.
- `StripCustomization` and the diary's link to the Roll carry the version wherever a look is turned into a strip render.

**Acceptance:**
- A v1 Roll photo renders **pixel-identical to 1.2.1** in the Roll, viewer and export. This is a regression test, kept as a fixed image in the tests.
- Opening it in the editor shows v2. Save stores v2. Discard keeps v1.
- Codable round-trips: no key → 1, and v2 stays 2.
- A strip made from a mix of v1 and v2 photos renders each one with its own version.
- `PersistenceTests`, `FilmStockMigrationTests` and `StripLookRegressionTests` pass.

**Files:** `Models/FilmLook.swift`, `Models/StripCustomization.swift`, `Features/Camera/FilmModel.swift`, `Features/Camera/ImageProcessor.swift`, `Constants+ImageProcessing.swift`, `Features/PhotoEdit/PhotoEditViewModel.swift`.

## F-122-C — Shadows and Highlights tools (photo editor)

**UI:**
- Two tools straight after Exposure in the editor's tool row, on the same tick scrubber.
- Range −100…+100 in steps of 1, with firm ticks at 0 and ±50, and Reset to 0.
- The readout is "+25" / "−40". VoiceOver adjusts in steps of 5 and reads the value.
- They are not on the strip screen, the camera or the Settings default look.

**What they do** (on the film, not a curve applied on top):
- **Shadows** moves the toe and the print's black point together.
  - + opens the shadows and lifts the black slightly.
  - − deepens them, down to a floor so it can't fully clip.
- **Highlights** moves the shoulder and the white roll-off.
  - − brings back highlight detail with a longer roll-off.
  - + brightens the highlights and adds snap.
- **Stock Off:** both apply as simple tone controls in the same places, so they still work without a stock.
- Stored as `FilmLook.shadows` and `FilmLook.highlights` (Double, default 0). Old looks without the keys decode as 0.

**Acceptance:**
- At 0 the render is pixel-identical to the look without the tools (add to `OffIsIdentityTests`).
- The output is monotonic at −100 and +100 on every stock.
- + Shadows never darkens a shadow, and − Highlights never brightens a highlight.
- The output is deterministic.
- Codable round-trips.
- "Reset to stock defaults" sets both back to 0.

**Files:** `FilmLook.swift`, `FilmModel.swift`, `ImageProcessor.swift`, `PhotoEditViewModel.swift`, `PhotoEditView.swift`, `Constants+PhotoEdit*.swift`, `Constants+ScrubberUI.swift`.

## F-122-D — "Frmrr" in visible text

**Change these strings:**
- `SettingsView.swift`: "Tips show again the next time you open frmr." and "frmr works fully offline…" → **Frmrr**.
- `NSCameraUsageDescription` (both configurations): "frmr uses the camera…" → "**Frmrr** uses the camera…".
- `NSPhotoLibraryAddUsageDescription` (both configurations): "**Filum** saves finished film strips…" → "**Frmrr** saves…". This was an old name that was never changed.
- Sweep every other user-visible string (tips, share text, alerts, empty states, accessibility labels) and change any "frmr" or "Filum" to "Frmrr".

**Unchanged:** code identifiers, logger subsystems, queue labels, accessibility identifiers, the project, targets, bundle ID and file names.

**Acceptance:** a grep for `frmr` / `Filum` in user-facing strings (`Text(`, labels, alerts, plist descriptions) finds nothing. The UI tests still find their accessibility identifiers.

---

## F-122-F — Crop tool (every photo)

**UI:**
- A **Crop** tool in the editor's tool row (after Highlights), for camera shots and imports alike.
- Presets: **Original, Free, 3:4, 4:5, 1:1, 16:9**, with a portrait/landscape swap for the fixed ratios.
- Drag the corners or edges to resize and drag the photo inside the frame to position it, with a rule-of-thirds overlay while dragging.
- Reset brings back the whole frame.
- Not included: rotate, straighten and flip.

**Storage:**
- Non-destructive. The crop is saved with the look as `FilmLook.crop`, a normalised rect (0…1) relative to the upright original. nil means no crop.
- The original is never changed. Old looks without the key have no crop.

**Where the crop applies:**
- **Applies:** Roll thumbnails, the photo viewer, **diary entries** (thumbnail, detail and prompt screen), and Download/export.
- **Doesn't apply:** strips. They use the full photo with their existing fit.

**Pipeline:** the crop is taken before the film stages, so grain, vignette and light leaks are laid out on the cropped frame. Effects whose size depends on the frame are scaled to the cropped size.

**Acceptance:**
- A cropped photo shows cropped in the Roll, the viewer, its entry and the exported file, and full in a strip.
- Reset brings back the full frame.
- A crop survives re-editing, and changing the stock keeps it.
- A minimum crop size (constant) is enforced.
- VoiceOver can choose a preset.
- `RollAndPhotoEditTests` and `DisplayThumbnailTests` pass.

## F-122-E — Import from gallery (Library → Roll)

**Flow:**
1. An **Import** (+) button at the top of Library → Roll opens the system `PhotosPicker`. It needs no full-library permission, and the app stays offline.
2. Pick **up to 10** photos (constant).
3. The photo editor opens on each in turn, with a "2 of 5" counter. Actions:
   - **Save to roll**
   - **Skip**
   - **Apply to rest**: saves this look, crop excluded, to every photo left in the batch, then finishes.
   - **Cancel** stops the batch. Photos already saved stay.
4. Each import starts with the look **Off**, at the current film model version (v2).

**Details:**
- **Develop from RAW when present:** if a pick has a ProRAW or DNG version, develop it through the same RAW path as camera shots (`ImageProcessor.process(rawData:)`). Otherwise use the HEIC or JPEG (decoded to the editor's working format, with orientation applied).
- **Date:** the import date (`capturedAt` = now), so imports appear under today in the Roll.
- **Privacy:** the copy frmr keeps and anything exported from it have **GPS and other metadata removed**.
- **Badge:** a small "Imported" mark on Roll thumbnails and in the photo viewer. This needs a new `RollPhoto.source` (camera / imported), where old photos decode as camera.
- **Continue to diary:** available on imports like any other Roll photo without an entry.
- **Errors:** a pick that can't be read or loaded shows one error, and the batch continues with the rest.
- Large images (panoramas, 48 MP) are downscaled to the camera's working size on import, so the editor stays fast.

**Acceptance:**
- Importing a batch of HEIC, JPEG, ProRAW, a panorama and a screenshot puts all five into today's Roll, with the badge, no location data and each chosen look.
- Skip and Cancel behave as described.
- Apply to rest gives the rest the same look, without the crop.
- An unreadable item shows one error and doesn't stop the batch.
- Memory stays bounded on a 10 × 48 MP batch.
- Old Roll photos have no badge.
- Unit tests cover metadata removal, RAW detection, `source` decoding and the batch state machine. A UI test covers the Import → Save → Roll path.

**Files:** `Features/Library/RollView.swift`, `Features/Roll/RollViewModel.swift`, `Models/RollPhoto.swift`, `Features/PhotoEdit/PhotoEditViewModel.swift` / `PhotoEditView.swift` (batch mode), `ImageProcessor.swift` (import decode), `Constants+Roll*.swift`.

**Unchanged:** Film strip mode's existing gallery button (photos go into slots as they are).

---

## Order of work (one Sonnet agent, step by step)

| Step | Work | Gate |
|---|---|---|
| 1 | BUG-122-01 and BUG-122-02 (camera) | Lead verifies; user checks the flip on the phone |
| 2 | F-122-B versioning, then F-122-D rename | v1 pixel-identical regression passes |
| 3 | F-122-A calibration and the before/after sheet | **Stops for user approval of the sheet** |
| 4 | F-122-C Shadows and Highlights | Identity and monotonicity tests |
| 5 | F-122-F Crop | Lead verifies |
| 6 | F-122-E Gallery import (reuses the editor, crop and versioning) | Lead verifies |
| 7 | QA pass, `all` test tier, docs | Ready for device checks |

Each handoff uses the template in `.claude/agents/README.md`. The agent runs the `suite` and `fast` tiers, and the lead runs `all`. Film-look steps also update `docs/film-simulation.md`.

## Docs to update as each step lands

- This spec's Implementation status.
- `CHANGELOG.md`: a "1.2.2 (in progress)" section in plain language.
- README "What it does", `project.md` §1 and the CLAUDE.md "What this app is" section: add gallery import, crop, and Shadows/Highlights.

## Open questions (proposed defaults)

| # | Question | Proposed default |
|---|---|---|
| 122-1 | This is large for a .x.2 release. Split crop and import into 1.3.0? | Keep it all in 1.2.2 (no answer yet) |
| 122-2 | Should Apply to rest also copy the crop? | No: each photo has its own shape |
| 122-3 | Maximum photos per import | 10 |
| 122-4 | Can a re-edited v1 photo be reverted to v1? | No: the editor always moves it to v2 |

## Implementation status

| Step | Status |
|---|---|
| 1 — BUG-122-01, BUG-122-02 | **Done; user confirmed on device (2026-10-28).** Unit tests: 367/367 pass, including the new `CameraSwitchTests` (6). The camera input swap now sets up the video connection before commit, and the frame sink drops the old camera's frame. A `CameraViewModel` state machine (`isSwitchingCamera`, `flipTransition`, 1.5 s timeout, generation counter) drives `FlipTransitionOverlay`. Device-only checks: 20 flips per stock, the first photo after a flip, the stock-Off snapshot (`drawHierarchy` may come out black), Reduce Motion. The "configured before commit" test needs a real camera and isn't automated. |
| 2–7 | Not started |

**Environment note (2026-10-27):** Xcode now has only the iOS 27.0 simulator runtime, so the iOS 26.x role simulators are unavailable. `frmr-lead` was recreated on iOS 27.0. The other roles (`frmr-backend`, the `frmr-ui-*` shards and the rest) still need recreating before agents can run tests or the UI tier can run.
