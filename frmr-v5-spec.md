# frmr — v5 Feature Specification (draft)

**Date:** 2026-10-21
**Status:** Draft from brainstorming with the user. Not started.
**Baseline:** v4 (Parts 1 and 2) on `main` (`593d36c`): 218 frmrTests and 6 UI tests pass.
**Context files:** `CLAUDE.md`, `project.md`, `frmr-v4-spec.md` (v5 reuses its `FilmModel`, `renderFullLook`, `FilmPreviewRenderer`, `FilmStockControl`, `DiaryReviewView` and `FilmLookCache`), `.claude/skills/ios-camera-orientation/SKILL.md`.
**Agent rule:** every sub-agent for v5 runs on **Sonnet** (`model: "sonnet"`).

---

## Overview

v5 adds a **Photo** mode: a camera made purely for taking film photos. It becomes the default mode, alongside Diary and Film strip.
- **Before the shot:** proper control over film stock, white balance and exposure.
- **After every shot:** an edit screen to change the stock, print and effects.
- **Storage:** photos live in a non-destructive in-app **Roll** that can be re-edited, exported and used in strips.

| # | Feature | Summary |
|---|---|---|
| F1 | Photo mode is the main screen | The app opens on the camera in Photo mode every launch; Diary and Film strip are options picked from the mode switch. |
| F2 | Stock dial | Swipeable film-stock dial above the shutter, inspired by a camera's film-simulation dial. Live film preview stays on. |
| F3 | White balance and exposure | WB presets plus a fine-tune panel (Kelvin and tint). An exposure compensation chip with a readout; swipe-EV stays. |
| F4 | Edit after every shot | `PhotoEditView`: Film / Print / Effects tabs, hold to compare, Retake, Download, Discard, Save to roll. |
| F5 | Effect strength sliders everywhere | Halation, Haze (renamed bloom), Light leak, Grain and Vignette become 0–100% sliders in the Photo editor, strip screen, diary review and Settings. |
| F6 | Roll | Library gets Roll / Entries / Strips tabs. The Roll keeps originals plus their look; re-edit, export, delete, and use in film strips. |

## Decisions made by the user (2026-10-21)

| Question | Decision |
|---|---|
| Where Photo mode lives | **The normal camera is the main screen on entering the app**; Diary and Film strip are options the user selects (follow-up, 2026-10-21). |
| Where photos go | **In-app Roll plus export.** The original and its settings are kept for re-editing; export to Photos on demand. |
| Pre-shot control | **Stock dial + WB (presets and Kelvin/tint) + exposure compensation.** No ISO, shutter or manual focus. |
| Post-shot controls | **Look** (stock, print, B&W) and **effects with sliders**. Not light/colour re-development, not crop. |
| After each shot | **Edit screen every time**, then back to the camera. |
| "Hazing" | **The existing bloom, renamed "Haze", with a strength slider.** |
| Sliders | **Replace on/off toggles everywhere.** |
| Roll in Library | **Roll tab, usable when making film strips.** |

## Research basis

**Film-first camera apps (Hipstamatic, Dazz)** choose the film before the shot, by swiping through films; Hipstamatic offers a separate "Pro" interface for more manual control.

**Pro camera apps (Halide):**
- manual controls are one toggle or gesture away from the viewfinder, modelled on physical dials;
- white balance is a small preset set;
- the layout is customisable.

**Photo editors** use a bottom tool bar where each tool opens its own row of sliders, with hold-to-compare or a split before/after view.

**frmr's own v4 work:**
- The live viewfinder already shows the cube look.
- `renderFullLook` already produces the full look at any size.
- The review screen proves the after-shot flow.

**Sources:**
- Hipstamatic: [Cult of Mac review](https://www.cultofmac.com/reviews/review-hipstamatic-is-the-most-retro-of-iphone-retro-photography-apps), [Macworld](https://www.macworld.com/article/203251/hipstamatic.html)
- Dazz: [App Store listing](https://apps.apple.com/app/1422471180)
- Halide: [Lux, "Introducing Halide"](https://www.lux.camera/introducing-halide/), [iThinkDiff](https://www.ithinkdiff.com/halide-camera-app-iphone-manual-controls/)
- Photo-editor UX: [Superside](https://superside.com/blog/ux-design-series-photo-editing-apps), [Framer image compare](https://www.framer.com/community/marketplace/components/imagecompare/)

---

## F1 — Photo mode is the main screen

**User decision (2026-10-21):** the normal photo camera is the main screen when the user enters the app. Diary and Film strip are options the user selects from it.

- **Launch:** the app already opens on the Camera tab (`OnboardingViewModel.selectedTab = .camera`). v5 makes it open in **Photo** mode on every launch.
  - `CameraViewModel.Mode` gains `.photo` and its default changes from `.diary` to `.photo`.
  - The stored capture-mode default (`DefaultsKeys.captureMode`) no longer decides the launch mode. Diary or Film strip is used only while the user picks it in that session (OPEN v5-9).
  - Settings' default-mode option is removed or replaced (OPEN v5-9).
- **Mode switch:** icon-only, following the v3 rotate-in-place rules.
  - Photo comes first and is selected at launch, then Diary, then Film strip. Each has an accessibility label.
  - Picking Diary or Film strip switches the same camera screen into that flow, exactly as in v4. Switching back to Photo restores the stock dial chrome.
- **Walkthrough:** the copy introduces the camera as the main screen, with Diary and Film strip as options (OPEN v5-1).

## F2 — Stock dial

- A horizontal, snapping dial of the seven stocks (Off + six) above the shutter, centred on the selected stock. It shows the short code; the full name appears in a caption under it.
- It replaces the v4 collapsible Film chip in Photo mode. Diary and Film strip keep the chip (OPEN v5-2: should they get the dial too?).
- Selection drives `CameraViewModel.filmStock`, the live preview and the stock of the next shot.
- Haptic tick per detent.
- **Rotation:** the dial is a wide control, so it can't rotate in place. Its strip stays fixed; only each code label counter-rotates in landscape. If labels collide, they stay upright, like the photobooth caption exception (OPEN v5-3).

## F3 — White balance and exposure

- **WB chip:** tapping it opens a compact panel with the presets (Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent), plus **Kelvin** (2500–9000 K) and **Tint** (−50…+50) sliders.
  - The sliders map to device gains: `deviceWhiteBalanceGains(for: temperatureAndTint)`, clamped to `maxWhiteBalanceGain`, set on the session queue.
  - The chip reads "AUTO" or the Kelvin value.
- **Exposure:** an EV chip shows the current bias (e.g. "+0.3"). Tapping it opens an EV slider (−2…+2, ⅓ steps). Swipe-EV on the viewfinder keeps working, and the two stay in sync.
- **Panels:** only one of Film, WB and EV is open at a time, extending v4's "one list open at a time" rule.
- **Persistence:** the WB and EV choices persist per mode? (OPEN v5-4; default: reset on launch, as today.)

## F4 — Edit after every shot (`PhotoEditView`)

- Presented after each Photo-mode capture, the same way as the diary review. The JPEG preview shows first, then is replaced by the RAW once it develops.
- **Top bar:**
  - Retake (discard, back to camera)
  - "Hold to compare" (press and hold the photo to see the photo without the look)
  - Download (top right: full-resolution HEIC to Photos, as in v4 F13)
- **Photo area:** the photo rendered in its look at screen size, debounced so the last change wins.
- **Tool tabs:**
  - **Film:** stock chips.
  - **Print:** print chips and the B&W toggle.
  - **Effects:** strength sliders for Halation, Haze, Light leak, Grain and Vignette.
- **Bottom row:**
  - **Discard** (secondary, left)
  - **Save to roll** (primary, right): saves the original plus its `FilmLook`, then returns to the camera.
- **Effect defaults** come from the stock, and a "Reset" action restores them (OPEN v5-5: where it goes).

## F5 — Effect strength sliders everywhere

**New shared value type `FilmLook`:** `stock`, `print?`, `blackAndWhite`, and `strengths` for halation, haze, lightLeak, grain and vignette, each 0…1.
- It replaces `FilmEffects` booleans in `StripCustomization`, diary review, Settings defaults and the new Roll.
- **Migration:** an effect that was on becomes the stock's default strength; one that was off becomes 0. Haze is the renamed bloom.

**Pipeline:** `ImageProcessor` scales each effect by its strength. Rules:
- 0 must be pixel-identical to "off".
- 1 equals the current v4 strength.
- The slider range may go above v4's strength (OPEN v5-6: max multiplier).
- Grain strength multiplies the stock's grain intensity.

**Vignette** becomes a strip/photo-time effect (overturns v4-4). Its default is 0, so existing looks don't change.

**Where it appears:**
- Sliders replace the toggles on the strip screen and in Settings.
- The diary review keeps stock chips, plus an Effects tab.

**Determinism unchanged:** seeds still come from capture time and frame index.

## F6 — Roll

**New SwiftData model `RollPhoto`:**
- `id`, `capturedAt`, `photoPath` (the original developed photo)
- `lookData` (Codable `FilmLook`)
- `editedAt`

This is a lightweight additive schema change.

**Library:** tabs **Roll / Entries / Strips**, with Roll first.
- The Roll is a grid of thumbnails rendered through `FilmLookCache` with each photo's look.
- Tapping a photo opens `PhotoEditView` in re-edit mode: Save updates the look, Discard leaves it unchanged, and Delete removes the photo after a confirmation.
- Export to Photos is available from the editor and from a multi-select action.

**Film strips from the Roll:** the Film strip creator can pick up to 4 Roll photos, alongside the camera and gallery options. Each frame keeps its own `FilmLook` under "As shot".

**Clear diary:** Settings → "Clear diary" does not clear the Roll. A separate "Clear roll" option exists (OPEN v5-7).

---

## Constraints (unchanged)

- Offline; no AI; no third-party dependencies.
- No automatic export: saving to Photos only on Download or Export.
- Every number lives in `Constants`; `// OPEN:` markers for open decisions.
- Never call `CIImage(image:)` on a photo.
- Personal test photos stay outside the repo (the gated sample tests).
- Run tests with `-parallel-testing-enabled NO`.

## Open decisions introduced by v5

| # | Decision | Default |
|---|---|---|
| v5-1 | Walkthrough step for Photo mode | Add one step: "Photo: shoot on film" |
| v5-2 | Stock dial in Diary and Film strip modes too | No, they keep the chip |
| v5-3 | Dial labels in landscape | Labels counter-rotate; strip fixed |
| v5-4 | Persist WB and EV between launches | No (reset on launch) |
| v5-5 | Where "Reset to stock defaults" lives | Effects tab header |
| v5-6 | Slider maximum relative to v4 strength | 1.5× |
| v5-7 | "Clear roll" in Settings | Yes, separate from "Clear diary", with confirmation |
| v5-8 | Roll photo used in a strip: link or copy | Link (the strip renders the Roll photo's current look at generate time) |
| v5-9 | Remember Diary/Film strip across launches, and Settings' default-mode option | Always launch in Photo; remove the default-mode option from Settings |

## Proposed sequencing (agents on Sonnet)

1. **Backend:** `FilmLook` model and migration, effect-strength pipeline (including vignette), `RollPhoto` model, `CameraMode.photo` with default migration, WB Kelvin/tint and EV API, and edit-session ViewModel (`PhotoEditViewModel`). Unit tests.
2. **Frontend** (after step 1's API): Photo mode chrome (stock dial, WB panel, EV chip), `PhotoEditView`, Library Roll tab, Roll picker in the Film strip creator, sliders on the strip screen and in Settings and the diary review. UI tests through a DEBUG fixture.
3. **QA:** regressions (the v4 orientation and determinism suites; slider 0 equals off; slider 1 equals v4), Roll persistence and re-edit, a strip from the Roll, and the device checklist.
4. **Lead:** docs (CHANGELOG, README, project.md, CLAUDE.md), then commit and push on user approval.

## Definition of done (v5)

- [ ] All v1–v4 criteria still pass
- [ ] The app opens on the camera in Photo mode every launch; Diary and Film strip are selectable and behave as in v4
- [ ] Stock dial, WB panel (presets plus Kelvin/tint) and EV chip work and follow the rotation rules
- [ ] Every Photo shot opens the editor. Save stores the original plus its look in the Roll; Discard and Retake leave nothing behind; Download saves a full-resolution HEIC.
- [ ] Sliders everywhere: 0 is pixel-identical to off; existing looks render the same after migration
- [ ] Roll tab: re-edit, export, delete; Roll photos usable in strips
- [ ] Zero warnings; guard clean; OPEN markers; docs updated

## Implementation status — v5 build

| Item | Status |
|---|---|
| Backend step 1 (Sonnet agent) | ✅ 2026-10-21. Lead re-ran it: **305 frmrTests pass** (+87), zero Swift warnings, guard clean (44 OPEN), no view files touched. |
| F1 model | `CameraViewModel.Mode` = `.photo` / `.diary` / `.photobooth` (`CaseIterable`, labelled). Launch is always `.photo` (`launchModeFollowsStoredCaptureMode = false`, v5-9). Settings had no default-mode option, so there is nothing to remove. Views pending. |
| F5 `FilmLook` | `Models/FilmLook.swift`: stock, `printStock`, B&W, `Strengths` (halation, haze, lightLeak, grain, vignette; 0…1.5, where 1 = v4). Strength 0 is pixel-identical to off. New vignette effect (default 0; overturns v4-4). Legacy Bool, `bloom` and ISO shapes migrate. `StripCustomization.effects` is kept as a Bool facade until QA updates its two regression files. Sliders pending frontend. |
| F6 Roll | `Models/RollPhoto.swift` (additive SwiftData) and `RollViewModel` (newest-first list, re-edit, delete, Clear roll, batched HEIC export, selection limited to 4, linked strip items). Library tab, strip picker and Settings "Clear roll" pending frontend. |
| F3 WB and EV | Kelvin 2500–9000 / tint ±50 mapped to clamped device gains on the session queue; EV in ⅓-stop steps from −2 to +2, shared by the chip and the swipe; one panel open at a time; reset on launch (v5-4). Chips and panels pending frontend; device check pending. |
| F4 `PhotoEditViewModel` | Shared `FilmLookRenderScheduler` (JPEG→RAW swap, last-wins render) is also used by the diary review; compare, reset, Download (full-res HEIC, waits for RAW), save to Roll, discard, retake, re-edit and delete. `Constants.PhotoEdit.presentsEditStep = false` until `PhotoEditView` exists. |
| Test consolidation (user-approved 2026-10-21) | Queued after the frontend round. One-off QA pass (Sonnet), allowed to merge and delete tests across all owners' files, with no loss of coverage. Scope:<br>• Merge the repeated themes (strength 0 / off = identity, seed determinism, single-case orientation tests covered by QA's matrix, paper texture) into parameterised tests.<br>• Delete the Xcode template UI tests.<br>• Split the 1,818-line `frmrTests.swift` into themed files.<br>• Add `docs/testing.md` with a "search before adding a test" rule.<br>• Report the before/after test lists, mapped to the invariants in `docs/film-simulation.md`. |
| Frontend (Sonnet agent) | ✅ 2026-10-21.<br>• F1: 3-way icon mode switch (Photo first) and Photo launch; the shutter routes to `captureForPhoto()`.<br>• F2: `StockDial` (snapping, labels counter-rotate, `.sensoryFeedback` detents).<br>• F3: WB and EV chips with panels, one open at a time.<br>• F4: `PhotoEditView` (Film / Print / Effects, hold-to-compare, Download, Discard / Save to roll, re-edit with Delete); `presentsEditStep = true`.<br>• F5: sliders on the strip screen, Settings (the "Remember white balance" toggle is removed) and diary review; `look` is passed on Save/Skip.<br>• F6: Library Roll / Entries / Strips (Roll first), select up to 4 → Export or Make strip, empty state, Settings "Clear roll"; the last-photo thumbnail by the shutter opens its editor.<br>Lead check: **307 frmrTests pass**, zero warnings, guard clean; DEBUG fixtures `-UITestPhotoEdit` and `-UITestSeedRoll` are inside `#if DEBUG`; screenshots of the edit Effects tab and the camera dial checked. |
| Follow-ups (backend, Sonnet) | Library `.roll` tab moved into `LibraryViewModel`; the walkthrough camera copy is stale (v5-1); the strip-complete haptic fires on every slider re-render. |
| Follow-ups (backend) | ✅ Library `.roll` tab moved into `LibraryViewModel`; walkthrough camera copy updated; the strip-complete haptic fires once per strip screen. |
| Test consolidation (QA, Sonnet) | ✅ Unit tests 310 → **283** (26 parameterised tests, 151 cases; 58 suites; `frmrTests.swift` split into themed files plus `TestSupport.swift`; new `OffIsIdentityTests`). UI tests 14 → **11** (Xcode templates removed). Every removed test is mapped in `qa/test-consolidation/mapping.md`; one gap closed (`colourMatrixRowsSumToOne`). New `docs/testing.md`. Lead re-run: **283 pass**, zero warnings, guard clean. Note: `DiaryReviewUITests.testCameraFilmControlExpandsAndCollapses` was flaky once at baseline. |
