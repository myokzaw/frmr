# frmr — 1.2.2 plan (draft)

**Date:** 2026-10-27
**Status:** In progress. Every feature step is done, confirmed by the user on device and committed. Step 7 (QA and docs) is under way.
**Version:** app version (`MARKETING_VERSION`) 1.2.1 → **1.2.2**. The home-screen name stays **Frmrr**.
**Branch:** `v1.2.2`, made from `main` @ `90795e0` when work starts.
**Agent rule:** **one Sonnet agent** for this release, working one step at a time (the user asked for this on 2026-10-27, instead of the usual two per round). The lead checks each step, runs the `all` test tier and writes the docs.

## Scope

| ID | What | Kind |
|---|---|---|
| BUG-122-01 | Orientation glitch for a moment when flipping front/back | Bug |
| BUG-122-02 | Viewfinder freezes when flipping; replace with a blur-and-flip transition | Bug |
| BUG-122-03 | App crashes when taking a digitally zoomed photo (user, 2026-11-02) | Bug |
| F-122-G | Digital zoom on RAW (crop after capture) and a Zoom sheet | Feature |
| F-122-H | Exposure, Zoom and White balance swap in for the stock dial instead of a sheet that covers the shutter | UI |
| F-122-I | Roll selection has no limit, for Delete and Export; Make strip takes 1 to 4 | UI |
| F-122-J | Contrast and Saturation tools in the editor | Film, UI |
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
- **Rotate 90°** (follow-up): a quarter turn clockwise per tap, stored as `FilmLook.quarterTurns`, applied before the crop and in strips too. Not included: straighten and flip.
- The swap works on every preset except 1:1.

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

## F-122-G — Digital zoom on RAW, with a Zoom sheet (user, 2026-11-02)

**Why:** BUG-122-03 is fixed by taking a processed-only photo when digitally zoomed, so zoomed shots lose the RAW development. The user wants zoomed shots to stay RAW, and to see how far they're zoomed.

**Decisions (user, 2026-11-02):**

| Question | Decision |
|---|---|
| Zoom control | **A sheet like Exposure**, with a ruler |
| Where it opens | **Tap the lens button you're already on** (0.5×, 1× or tele). Tapping another lens switches lens as today. |
| Range | **Within the current lens only.** The lens buttons work as today, and the ruler crops the chosen lens. |
| Maximum | **3× past each lens**, a constant |
| Ruler | **0.1× steps**: a click per step, a firm click at each whole ×, and −/+ buttons, like the camera's Exposure ruler |
| Pinch | **Kept.** It moves the same value; double-tap resets to 1×. |
| Front camera | **No zoom** (stays 1×) |
| Film strip mode | **Zoom applies to the slot** (user, 2026-11-03): the slot image is cut to the zoomed framing |
| How it's saved | **As an editable crop** (F-122-F): the whole RAW is kept, and the Crop tool can widen it later |

**How it works:**
- The capture device's `videoZoomFactor` stays at **1.0**, so Bayer RAW is always allowed. Digital zoom becomes an app-side value, `zoom` (1…3), per lens; switching lens resets it to 1×.
- **Viewfinder:** both previews are scaled about their centre by `zoom`: the plain `AVCaptureVideoPreviewLayer` (stock Off) and the Metal film preview. The grid and overlays stay on the visible frame. Tap-to-focus and exposure-point mapping account for the scale, so the point you tap is the point that focuses.
- **Capture:** RAW + processed as today. The saved look gets `crop` = the centred rect of size 1/zoom × 1/zoom in the upright photo, preset Original, at the shot's orientation. It applies after RAW development, through the existing crop path, so the Roll, viewer, entries and export show the zoomed frame, and strips use the full photo (F-122-F). At 1× no crop is stored.
- **Lens button label:** it shows the current zoom while zoomed ("2.4×"), and its own lens value at 1×.
- **Sheet:** a "Zoom" title and a "2.4×" readout, like the Exposure panel, with − / ruler / +. It opens one sheet at a time with WB and EV.
- **Safety net:** BUG-122-03's processed-only fallback stays in case the device zoom is ever not 1.
- **Known trade-off:** the viewfinder gets softer at high zoom, because it enlarges the video frame. The saved photo is cropped from the full RAW, at about 12 MP / zoom².

**Acceptance:**
- No crash at any zoom on any lens.
- A zoomed shot is RAW-developed: `rawData` is present and the photo goes through the RAW path.
- The saved crop matches the framed area (centre and size within 1%) in portrait and landscape.
- The Crop tool can widen it back to the full photo.
- Pinch, ruler and −/+ all move the same value, which is clamped to 1…3.
- Switching lens resets to 1×.
- Tap-to-focus hits the tapped point when zoomed.
- The front camera shows no zoom control.
- Tests: zoom → crop rect (pure), preview scale and tap-point mapping (pure), the view-model zoom state, and capture storing the crop.

## F-122-H — Camera controls swap in for the dial (user, 2026-11-03)

**Why:** on device, the Exposure and Zoom sheets (and White balance) covered the shutter row, so the user had to close them to take a picture.

**Decisions (user, 2026-11-03):**
- Exposure (±), Zoom (tap the selected lens) and White balance (thermometer) **replace the stock dial in its slot**, like the iOS Camera. The shutter row never moves and is always usable. These three no longer use a sheet.
- To close a control, tap its button again or its ×. Opening another control swaps directly; one is open at a time.
- **A control stays open after a shot.** It closes itself after 6 s with no interaction (`controlIdleTimeout`). Reduce Motion swaps it without a slide.
- **White balance** gets a scrolling preset row plus one slider, with a Kelvin | Tint switch (`camera.wb.axis`).

**Acceptance:**
- The shutter is hittable while each control is open.
- Close by button, by ×, and by the idle timeout all work.
- A capture doesn't close the control.
- It works in both camera layouts, in landscape (the chips' glyphs turn and the cards stay upright) and in Film strip mode.

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
| 2 — F-122-B, F-122-D | **Done; user OK'd (2026-11-02).** Unit tests: 379/379 pass, including the slow suites. `FilmLook.modelVersion` (missing key → 1, new looks → 2) and `FilmModelParameters` (`.v1`, `.v2`, `.current`, `.forVersion`) are threaded through `FilmModel`, `ImageProcessor`, the preview cube, `FilmSwatch`, `StripCustomization`, strips and `DiaryEntry`. The cube cache keys on the version. The editor opens a v1 photo as v2; Discard keeps v1. Step 3 changes only `Constants.ImageProcessing.Film.ModelV2`, which is a copy of v1 for now; `printWhiteTarget` and the toe pivot are still shared by both versions. `FilmModelV1PinnedTests` pins SHA-256 fingerprints of all 48 stock × print × B&W v1 cubes, taken from the 1.2.1 code (0ae0e38), so v1 provably renders as 1.2.1. Renamed: the two Settings lines and both permission prompts ("Filum" was among them). No other visible "frmr" was found. |
| 3 — F-122-A | **Done; the user approved the before/after sheet (2026-11-02).** Unit tests: 388/388 pass; `FilmModelV1PinnedTests` still pins v1. v2 print blacks (/255, v1 → v2): Projection 3→10, Cinema 4→12, Lab 6→14, Matte 28→34. The new `NegativeProfile.shadowLift` (v1 = 0) adds `lift·27/4·t(1−t)²` to the toe below the pivot, so mid grey and up don't move. Per-stock lift: Portrait 0.080, Daylight 0.056, Mono 400 0.050, Cine 0.032, Mono 3200 0.028, Slide 0.012. The toe exponent (8) and pivot (0.18) are unchanged. `FilmModelV2ShadowTests` (8) covers lighter blacks, print and stock order, the 18/255 black ceiling, monotonicity and mid grey within 4/255. `FilmCalibrationTests.portraitSkiesStayCyanNotLavender` is loosened to Off + 3° for v2: the lift moves a deep-navy patch 2.56°. Sheets are rendered from the user's DNGs to `qa/film-sheets/`, which is gitignored. |
| 4 — F-122-C | **Done; user confirmed (2026-11-02).** Unit tests: 408/408 pass. `FilmLook.shadows` and `.highlights` (−100…+100, step 1; old looks read 0) are carried through `StripCustomization`. `ToneStage` is a monotone curve in the print's sRGB-encoded output, pivot 0.5, applied as a 256-entry `CIColorCurves` table straight after the film cube (for Off, after gain/B&W), and skipped at 0/0. It is not in the cube because scrubbing would rebuild the cube on every tick. Preview and save share `filmLook(...)`. Tuning is in `Constants.ImageProcessing.Film.ToneControl`. Measured on Portrait 400 (/255 at linear 0.01, 0.05, 0.18, 0.6, 0.9): base 58, 95, 140, 219, 240; Shadows +100 73, 100, 140, 219, 240; Shadows −100 48, 92, 140, 219, 240; Highlights +100 58, 95, 141, 236, 251; Highlights −100 58, 95, 138, 181, 210. Lead note: +100 Shadows is gentle (peak lift about 17/255, black about 4/255). `shadowOpenAmount` 0.13 is the knob if the user wants more. |
| 4b — F-122-C follow-up (user, 2026-11-02) | **Done; user confirmed.** The user asked for more tactile sliders that make small changes easy, for the camera's exposure slider too, and for a stronger Shadows. `EffectScrubber` is now Photos-style: the marker is fixed at the centre and the ruler follows the finger (left raises the value). The drag is relative, so a touch changes nothing, and double-tap still resets. Tick spacing: tone 6pt, exposure 22pt, effects 10pt. A `.selection` haptic fires on every step, with a medium haptic at 0, ±50 (tone), whole stops and 100%. The camera `ExposurePanel` uses the same ruler instead of a system Slider; the WB sliders are unchanged. Shadows: `shadowOpenAmount` 0.13→0.26 and `shadowDeepenAmount` 0.55→0.7. Portrait 400 at linear 0.01: −100 46, 0 58, +100 88. The UI tests now drag the ruler instead of tapping its ends (`frmrUITests/ScrubberGestures.swift`). Unit tests: 411/411. UI tests: all pass on the new iOS 27 shard simulators. |
| 5 — F-122-F | **Done; confirmed by the user on device (2026-11-02).** Unit tests: 444/444; UI tests: all pass. `FilmLook.crop: CropRect?` is normalised to the upright original, top-left origin, and stores its preset and orientation; old looks read nil. `ImageProcessor.renderFullLook` crops first, in upright space, then re-tags to sensor space, so exposure, film and every frame-sized effect lay out on the crop. The crop applies to Roll thumbnails, the viewer, entries, the prompt screen and Download. Strips ignore it: `customization` carries no crop, and a test checks this. Reset to stock defaults keeps the crop; the Crop tool has its own Reset. `CropGeometry` holds the pure helpers; the minimum crop is 10% of the short side. `EntryLookImage` now re-renders on any look change (it used to key on the stock only). `FilmLookCache` decodes larger for small crops. Follow-up (2026-11-02): swap on Original/Free, Rotate 90° (`quarterTurns`, clockwise, also in strips), and a stand-in photo (turned+cropped, `ImageProcessor.geometryOnly`) so leaving the tool never flashes the old framing; unit tests 475/475. Device checks: rotate feel and haptic, the cross-fade, drag feel and overlapping handles on a small frame, haptics, VoiceOver, and a cropped RAW and EXIF-rotated shot everywhere. |
| 5b — crop follow-up (user, 2026-11-02) | **Done; confirmed by the user on device.** Unit tests: 476/476; UI tests: all pass. The swap now works on Original (largest centred frame in the other orientation) and Free (swaps w/h); only 1:1 is disabled. `FilmLook.quarterTurns` (0…3, Rotate button `rotate.right`, clockwise) is folded into the orientation tag before the crop and honoured in strips. The crop rect turns with the photo. Crop-tool Reset clears crop and turn. No flash on leaving the Crop tool: the VM shows a stand-in (the last render cropped, or the plain photo turned and cropped via `ImageProcessor.geometryOnly`) until the render lands, then cross-fades; Reduce Motion swaps instantly. Compare now shows the plain photo with its turn and crop. |
| BUG-122-03 | **Fixed; confirmed by the user on device (2026-11-02).** Cause: Bayer RAW capture requires `videoZoomFactor` and the photo connection's `videoScaleAndCropFactor` to be exactly 1. Anything else makes `capturePhoto` raise NSInvalidArgumentException, which Swift can't catch. Lenses (0.5×, 1×, tele) are separate devices at 1.0, so only in-between digital zoom crashed. Fix: `makePhotoSettings` requests RAW only when `CaptureSession.canCaptureBayerRaw` (zoom 1, not ramping, crop 1). Otherwise it takes the processed photo only, through the app's existing no-RAW path. Trade-off: digitally zoomed shots are developed from the processed JPEG, not RAW. `ZoomedCaptureTests` (4). Unit tests: 480/480. |
| F-122-G | **Done; confirmed by the user on device (2026-11-03).** Unit tests: 502/502; UI tests: all pass. The device `videoZoomFactor` is always 1, so every shot is RAW. Zoom is app-side (1…3, 0.1 steps) in `DigitalZoom.swift`. The plain preview uses `.scaleEffect`; the film preview scales in `previewImage(zoom:)`. Tap-to-focus goes through `DigitalZoom.unscaledPoint`. At capture, a 1/zoom centred `CropRect` (preset Original) is attached in both the editor flow and the straight-to-Roll flow. Film strip mode cuts the zoom into the slot image (`photoboothSlotImage`; user decision 2026-11-03), because strips ignore look crops. Tapping the selected lens opens the Zoom sheet; a single-lens phone shows one chip. Pinch, ruler and ± share `applyZoom`; double-tap resets. Lens switch and flip reset to 1×; the front camera has no zoom. Device `setZoom`/`zoomRange`/`clampedZoom` are removed. Known: on short phones the viewfinder is taller than 3:4, so the saved crop shows a little more at the sides (as unzoomed shots already do). |
| F-122-H | **Done; confirmed by the user on device (2026-11-03).** `CameraControlSheet` is replaced by `DialSlot`: a ZStack keeps the hidden dial for height, so Exposure and Zoom (about 62pt) fit the dial's roughly 72pt. WB is about 92pt, so the slot grows about 20pt while it's open. `CameraPanels.swift` is rewritten. The view model has `panelIdleTimeout` (injectable) and interaction pings. A viewfinder tap no longer closes these controls and counts as interaction. `CameraPanelTests` (12). The UI test is now `testWhiteBalanceAndExposureSwapInForTheDial`, which also checks the shutter is hittable while a control is open. Open: the never-run compact-height `dockedChrome` fallback has no dial slot. |
| F-122-G/H follow-up (user, 2026-11-03) | **Done; confirmed by the user on device.** Exposure and Zoom are one 44pt row: readout (52pt, amber, monospaced), ruler, ×. Only Exposure keeps −/+, and there's no title text. WB: presets + × on row 1, then Kelvin|Tint + slider. Zoom step is 0.2 (24pt per step), with firm ticks at whole ×. The preview follows the live, unsnapped value during a gesture (`liveZoom`) and glides to discrete changes: a 0.15s ease on the plain layer, and exponential smoothing in `FilmPreviewRenderer.draw` (τ 0.12s); Reduce Motion is instant. A pinch fires a detent per snapped step. Capture crops to `liveZoom ?? zoomFactor`. |
| 6 — F-122-E | **Done; confirmed by the user on device (2026-11-03).** Roll `+` (`roll.import`) opens `PhotosPicker` (max 10, images, `.current` encoding). A full-screen cover runs the editor per pick with a "2 of 5" counter, Skip / Apply to rest / Save, and Cancel (×). Retake is hidden during an import. Pure `ImportBatch` struct; `GalleryImportSession` loads one pick at a time. `GalleryImportDecoder`: RAW bytes go through `process(rawData:)`; HEIC/JPEG through an ImageIO thumbnail (orientation applied, long side ≤ 4032). Originals are written by `strippedJPEGData` (pixels + orientation only; a test checks no GPS/EXIF/TIFF). `RollPhoto.sourceRaw` defaults to "camera" (lightweight migration). Imported badge on Roll thumbnails and in the editor. `AppError.importFailed`. `GalleryImportTests` (26). No UI test, because the out-of-process picker isn't reliably drivable. Device risks: whether the picker hands back the DNG for RAW+JPEG/ProRAW assets, memory on 10 × 48 MP, and the alert when the last pick fails. |
| F-122-I | **Done; confirmed by the user on device (2026-11-03).** User: selecting stopped at 4, so deleting 10 photos took three rounds. `toggleSelection` has no limit. `canMakeStrip` (1 to 4) replaces `canAddToStrip`; a note above the bar ("A strip holds up to 4 photos") explains it rather than dropping photos silently, moved there from the bar after the user found two lines cramped. Export encodes to temporary HEIC files one at a time (`saveToCameraRoll(photoFiles:)`), still one all-or-nothing library change, removed afterwards. Badge numbers scale to fit three digits. Device check: memory and time on a large export. |
| F-122-J | **Done; confirmed by the user on device (2026-11-03).** User's choices: editor only; Saturation gentle and protecting skin; Contrast full range like Photos, so high values can undo the lighter blacks; in 1.2.2. `FilmLook.contrast` / `saturation` (−100…+100, step 1, omitted from storage at 0, so older looks read 0 and render unchanged). Contrast runs first in `ToneStage`'s curve (a gain S-curve up, a linear squeeze toward mid grey down), so Shadows and Highlights can still open what it crushed. `SaturationStage`: a 33-point cube in the print's encoded output, boost before vignette, haze, leak and grain so grain doesn't become colour noise, reduction after them so −100 is truly grey. Skipped when the look renders in black and white; the tool is hidden there and the editor leaves it if the look turns black and white. Strips carry both. After device feedback the value rings of every signed tool (Exposure, Shadows, Highlights, Contrast, Saturation) run clockwise for an increase and anticlockwise for a decrease (`ToolRing.arc`). Device check: how the ranges and the skin protection feel on real photos. |
| 7 | QA and docs: not started |

**Environment note (2026-10-27):** Xcode now has only the iOS 27.0 simulator runtime, so the iOS 26.x role simulators are unavailable. `frmr-lead` was recreated on iOS 27.0. The other roles (`frmr-backend`, the `frmr-ui-*` shards and the rest) still need recreating before agents can run tests or the UI tier can run.
