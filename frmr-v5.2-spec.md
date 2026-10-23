# frmr — v5.2 UI makeover (draft)

**Date:** 2026-10-21
**Status:** In progress (2026-10-22) on branch `v5.2-makeover` (from `v5-photo-camera` @ `26d8e66`, v5.1 pushed). Questions v5.2-5…10 use the proposed defaults (the user said go without answering them; they can be changed later).
**Source:** `research/v5.2-ui-makeover.md` (iOS design engineer, Opus) contains the full audit, competitive research with sources, design system, per-screen proposals, signature moments and roadmap.
**Agent rule:** build agents run on Sonnet.

## Decisions made by the user (2026-10-21)

| Question | Decision |
|---|---|
| Editor after every Photo shot | **Add a Settings toggle "Edit after each shot", default on.** Off means keep shooting and edit later from the Roll thumbnail. |
| Camera layout on tall phones | **Dial and shutter below a 3:4 viewfinder**, on black. Floating glass controls only on short phones. |
| Film strip buttons | **Mini-strip sheet:** the four slots become a small strip in the thumbnail position. Tapping it opens gallery / Roll / undo / Generate, keeping Photo and Strip chrome identical. |
| Walkthrough | **Replace the custom coach marks with TipKit tips** anchored to real controls. |

## F-EXP — Exposure in the editor (user request, 2026-10-22)

After taking a picture, the editor has an **Exposure** tool alongside the film tools.

**How it works:** the tool sets a new `FilmLook.exposure` value in EV.
- **Range and steps:** −2…+2 in ⅓-stop steps, matching the camera's EV control. Default 0.
- **Where in the pipeline:** applied to the photo **in linear light before the film cube**, by scaling scene exposure by 2^EV ahead of the negative curve. It therefore behaves like over- or under-exposing film: highlights roll off through the shoulder and shadows lift through the toe, rather than clipping like a plain brightness slider. Halation and grain follow, since they read the exposed image and the print density.
- **With stock Off:** exposure still applies as a plain linear 2^EV gain, so the photo counts as "altered" whenever exposure ≠ 0.
- **Where it applies:** stored per photo in the Roll (non-destructive, re-editable), Download, and diary entries via the live link. Strips render each frame's own exposure under As shot.

**UI:** the first tool in the editor toolbar, `plus.forwardslash.minus`, labelled "Exposure". It uses the same tick-mark scrubber with an EV readout ("+0.3 EV"), a firm tick at 0, a light tick each ⅓ stop, and reset to 0. VoiceOver adjusts it in ⅓-stop steps and reads the value.

**Tests:**
- 0 EV is pixel-identical to no change (add it to `OffIsIdentityTests`);
- +1 EV brightens mid grey monotonically and never makes the output darker;
- highlights compress, rather than clip, under film stocks;
- `FilmLook` Codable round-trip, with old looks without exposure decoding as 0;
- determinism.

**Owners:**
- **Backend:** `FilmLook.exposure`, Codable migration, pipeline stage, `PhotoEditViewModel` binding, tests, and an update to `docs/film-simulation.md` §3 (pipeline order) and §9 (recipes).
- **Frontend A:** the toolbar entry and the EV scrubber mode.

**Decided by the user (2026-10-22):**
- **v5.2-11:** Exposure is **per photo only**; the strip screen gets no strip-wide offset.
- **v5.2-12:** **exposure only**, with no separate highlights/shadows controls.

## Remaining open questions (proposed defaults)

| # | Question | Proposed default |
|---|---|---|
| v5.2-5 | Colour swatches on the stock dial, or plain codes | Swatches plus codes |
| v5.2-6 | Contact-sheet Roll: always dark, or paper in light mode | Paper in light mode, dark in dark mode |
| v5.2-7 | Strip screen "Archive": merge Save and Archive into one "Keep strip" | Yes |
| v5.2-8 | Adopt the system serif permanently instead of bundling Newsreader | Yes |
| v5.2-9 | Settings toggle for the richer film-advance haptic | Yes, default on |
| v5.2-10 | Tab bar | Keep for now; revisit after the camera layout lands |

## Already handed to the v5.1 agents (from the audit)

- **Contrast:** "Save to roll" on teal, tab tint on the dark camera, rust in dark mode, character count.
- **Touch targets:** 44pt minimum for the strip buttons.
- **Strip screen:** Close overlaps the strip; Save/Share/Archive are clipped.
- **Library:** the Roll's left-edge bleed, lists scrolling under the tab bar, Entries showing the response first, Strips in two columns.
- **Walkthrough:** the "Library" bubble appears on the Settings screen.
- **Accessibility:** Reduce Motion, Reduce Transparency, and Dynamic Type where text is touched.

## Roadmap

See `research/v5.2-ui-makeover.md` §7. The order:
1. A design-token PR by one agent first: Dynamic Type type roles, spacing, radii, colour roles with light and dark values, and the upgraded `frmrGlass`.
2. Then camera, restyle and backend agents in parallel (separate worktrees).
3. Then a QA accessibility pass.

## Carried over from v5.1 QA (fold into v5.2)

- **BUG-V51-02:** the flaky hold-to-compare UI poll.
- **BUG-V51-03:**
  - the editor hint is unreadable over light photos;
  - the Film chip row clips at the right edge;
  - Reduce Motion guards are missing on several animations;
  - view-body logic in `ContentView` and the modified-tools set;
  - raw hex colours in `ThemePalette+Accent`;
  - the Roll badge and delete-prompt counts treat a failed fetch as 0 (backend).
- **From the v5.1 agents' notes:**
  - the strip sheet stops above the bottom safe area, leaving a beige band in light mode;
  - large Dynamic Type sizes haven't been checked;
  - a dark-mode screenshot pass across all screens is still to do;
  - UI shards are balanced by test count, not time (`testStripScreenCyclesEveryStock` takes about 195 s).

## v5.2.1 — fixes and additions (user request, 2026-10-23)

**Status (2026-10-23):** built (backend and frontend, both Sonnet).
- BUG-01, BUG-02, F-PICK and F-GRID are done, plus the prompt-lag fix (1600 px display copy, and one `PromptCard` that keeps its identity through `AnyLayout`).
- Re-edit → prompt goes through the new `ReEditFlowView` (camera thumbnail and Roll).
- "Picked photos don't show" couldn't be reproduced in the model. The picker now shows a counter, badges and unpick, and the UI test checks the slot fills.
- Lead check: all unit and UI tests pass, the guard is clean, and the grid has the accessibility label "Grid: <style>".
- Device checks are pending.

### BUG-521-01 — White balance doesn't return to Auto
**Cause:** `CameraViewModel.chooseWhiteBalancePreset(.auto)` sets the mode to Auto but leaves `whiteBalanceKelvin` and `whiteBalanceTint` at the previous preset's values, so the panel's Kelvin and tint readouts still show, for example, "3200K" after you pick Auto. (`resetWhiteBalanceAndExposure()` already resets them; the preset path doesn't.)
- **Backend:**
  - On `.auto`, reset Kelvin and tint to `whiteBalanceManualStart*`.
  - Add `whiteBalanceKelvinText` and `whiteBalanceTintText` ("Auto" while on Auto and not custom; otherwise "5600K" and "+12").
  - Unit test: Tungsten → Auto, and slider → Auto. Both end at the start values with readouts "Auto", `isWhiteBalanceAdjusted == false` and chip text "AUTO".
- **Frontend:** `WhiteBalancePanel` shows the two new readout texts instead of formatting the numbers itself.
- **Device check:** after Auto, the viewfinder visibly re-meters (continuous auto white balance).

### BUG-521-02 — No "Continue to diary" when Edit after each shot is off
**Cause:** with the toggle off, each shot goes straight to the Roll. You edit it later from the thumbnail or from Library → Roll, which opens the editor in re-edit mode. `PhotoEditViewModel.canContinueToDiary` is `rollPhoto == nil && …` (v5.1-2: fresh captures only), so turning the toggle off leaves no way to write an entry.

Proposed default (the user can change it): offer Continue to diary on a Roll re-edit when the photo has **no linked entry yet**. A photo that already has one shows only Save, so it doesn't collect duplicate entries.
- **Backend:**
  - `canContinueToDiary` becomes true for a fresh capture, or for a re-edit whose linked-entry count is 0. That count is read once when the editor opens, from `linkedEntryCountIfKnown`, and a nil count hides the button.
  - In re-edit, `continueToDiary` saves the look onto the existing `RollPhoto` (as Save does) instead of inserting a new one, then sets `diaryContinuation` with that photo's ID.
  - Unit tests: fresh capture, re-edit with no entry, re-edit with an entry, unknown count.
- **Frontend:**
  - The camera-thumbnail editor already lives in the camera's cover (`EditorFlowView`), so the prompt opens there.
  - `RollView` presents its editor in a sheet of its own, so it needs the same editor → prompt hand-off. Reuse `EntryEditorView` through the same `pendingDiary` path, or a small Roll flow view that wraps both.
  - UI test: with Edit after each shot off, take a shot, open it from the thumbnail, check that Continue to diary is visible and that the prompt opens.

### BUG-521-03 — Keyboard doesn't come up on the prompt screen — **fixed (lead, 2026-10-23)**
**Cause:** before you start writing, the text box is only 120 pt tall, under the full-size photo. A tap on the empty paper below it, where you'd naturally tap, hit nothing, so the keyboard never appeared.
**Fix:** `EntryEditorView` makes the whole screen a tap target that focuses the text box. Buttons and the text view keep their own taps.
**Test:** `PromptKeyboardRegressionUITests`. Before the fix, a tap 80 pt below the box left it unfocused; it now gets keyboard focus. The two `DiaryFlowUITests` tests pass, as does the fast unit tier. The guard is clean.

### BUG-521-04 — App freezes and is killed when the keyboard opens on the prompt — **fixed (lead, 2026-10-23)**
**Evidence:** phone crash log `frmr-2026-10-22-205047.ips`: watchdog `0x8BADF00D`, with the main thread stuck in `CameraPreview.makeUIView` → `AVCaptureVideoPreviewLayer.setSession` → `AVCaptureSession commitConfiguration`.
**Cause:** the camera stays alive under the editor/prompt cover. Its `GeometryReader` received the keyboard's safe-area inset, so `chromePlacement` flipped from `.below` to `.overlay`. That swaps the viewfinder into another branch, which rebuilds `CameraPreview` and re-attaches the running session on the main thread, and the app hangs. The simulator has no camera session, so it never reproduced there.
**Fix:** `CameraView` applies `.ignoresSafeArea(.keyboard)`.
**Test:** `PromptKeyboardRegressionUITests.testRealCaptureThenTypingDoesNotHang` (real camera; skips on the simulator). The fix still needs checking on a device.
**Mac testing:** looked at and dropped. Xcode doesn't run UI tests on "Designed for iPhone" Macs, and unit tests there would need the Mac registered on the team. `test.sh` now also fails on `xcodebuild: error:`.

### F-STRIPUI — Strip screen uses the editor's layout (user request, 2026-10-23) — **done**
- **Change:** the controls sheet is gone. The screen is one column: the strip hero, the tool panel, `ToolIconBar` and Keep strip.
- **Tools:**
  - Film and Print are `PreviewRow` thumbs (now shared in `Shared/Components/PreviewRow.swift` and used by the editor too).
  - Paper is two swatches.
  - B&W sits under Print. The Print tool shows for every film, with "This film has no print to choose." where that applies, so B&W stays reachable.
- **Previews:** backend added `StripViewModel.stockPreviews`, `asShotPreview`, `printPreviews` and `requestPreviews(size:scale:)`. They render from the first frame, off the main thread, and are cached.
- **Tests:** `StripPreviewTests` (4). Lead check: fast unit pass, all UI pass, guard clean.
- **Device:** the swatch rim on the dark background; thumbs fill in; Keep strip stays on screen at large text.

### F-PICK — Counter in Pick from Roll
User decision: counter, numbered badges and tap to unpick.
- **Backend:**
  - `PhotoboothShot` gains `rollPhotoID: UUID?`, set by `add(rollPhoto:)`.
  - `PhotoboothViewModel` gains:
    - `slotNumber(forRollPhoto id: UUID) -> Int?` (1-based slot position);
    - `toggle(rollPhoto:)`, which adds the photo, or removes it if it's already in a slot, with later slots moving up;
    - `rollPickerTitle`, for example "2 of 4 picked". The count includes camera and gallery shots, since every slot counts.
  - Unit tests: add/remove/re-number; a full strip still allows unpicking; the same photo can't be picked twice.
- **Frontend:**
  - `RollPickerSheet` takes the photobooth view model.
  - Title: `rollPickerTitle`.
  - Each picked photo shows a `SelectionBadge` with its slot number (reuse the Roll's badge).
  - A tap toggles the photo; photos that aren't picked are disabled only when the strip is full.
  - The sheet no longer closes itself on the fourth pick. Done closes it.
  - VoiceOver: "Photo, picked, slot 2", with the hint "Removes it from the strip".
  - Update `StripScreenUITests` for the counter and unpick.

### F-GRID — Viewfinder grid in Settings
User decision: Off / Thirds / Square / Golden. Default Off. No level.
- **Backend:**
  - New `CameraGrid` enum (`off`, `thirds`, `square`, `golden`) with `label`.
  - A pure static `lineFractions(for:) -> [CGFloat]`: thirds `[1/3, 2/3]`, square `[1/4, 1/2, 3/4]`, golden `[0.382, 0.618]`, off `[]`. The same fractions apply on both axes.
  - Key: `Constants.DefaultsKeys.cameraGrid`. Unit tests for the fractions and the stored-value round trip, where an unknown value reads as Off.
- **Frontend:**
  - Settings → Camera section: a "Grid" picker.
  - `ViewfinderGridOverlay` sits inside the viewfinder frame only, in both Photo and Film strip modes, and is never shown in the editor.
  - Hairlines are 0.5 pt at white 35% with a faint dark shadow, from `Constants.CameraUI`.
  - The overlay doesn't block taps or pinches (`allowsHitTesting(false)`), is hidden from VoiceOver, and doesn't rotate, because the lines are symmetric.
  - UI test: set Thirds in Settings, and the camera shows `camera.grid`.

### F-ENTRYPICK and F-STRIPDEL (user request, 2026-10-23) — **done**
- **Bug:** "+" (Make today's strip) used every one of today's entries (`todaysItems`). More than 4 spilled into a second strip, and you couldn't drop one.
- **Entry picker:** "+" now opens `EntryStripPickerSheet` (`EntryStripPickerViewModel`). It defaults to the latest 4, lists entries newest first, uses chronological slot order, and has a counter, badges, unpick, and Cancel / Make strip. Strip items carry the entry's full look.
- **Delete:** the strip viewer gains Discard (`strip.detail.delete`, confirmed), and Settings gains Clear strips (`settings.clearStrips`). The new `LibraryViewModel.deleteStrip` and `clearStrips` remove the files and records; entries and photos stay.
- **Strip hero:** the top bar is a `.safeAreaInset`, so the strip no longer scrolls under the status bar.
- **Tests:** `EntryStripPickerTests`, `StripDeletionTests` and 3 UI tests. Lead: unit and all UI pass, guard clean.

### BUG-521-05 / BUG-521-06 — Library switch jumps; thumbnails stutter (user, 2026-10-23) — **fixed**
- **05 (the switch):**
  - **Cause:** the segmented control sat in `.principal`. Roll's trailing Select pushed it left, and Entries (no trailing item) re-centred it, so it moved and its glass morphed on every switch.
  - **Fix:** the control moves to `.topBarLeading`, with an empty principal so the title doesn't show. Roll's selection Cancel moves into Select's `primaryAction` slot.
  - **Checked:** a probe captured the control at the same frame (20, 61, 198×47) on all three tabs.
- **06 (thumbnails):**
  - **Cause:** every thumbnail decoded the full original (12–48 MP) at once, with no limit.
  - **Fix:** `ImageIOThumbnail` decodes at display size, upright, and `AsyncGate.display` allows 2 renders at a time, with cancelled waits dropped. Both are used by `FilmLookCache.displayImage`, for diary and Roll. Full-resolution export is unchanged. Tests: `DisplayThumbnailTests`.

### Round plan
- One backend and one frontend agent (Sonnet), covering all four items.
- Backend goes first: all three APIs are small. Frontend starts once backend hands back.
- The lead runs `fast`, the affected UI suites and the guard.
- No screenshots. The user checks on their phone.
- Docs: this section's status, CHANGELOG, README feature list (grid).

## Implementation status — v5.2

| Step | Status |
|---|---|
| v5.1 pushed; worktrees cleaned | ✅ `26d8e66` |
| M0 design tokens + M4 44pt floor (agent T, Sonnet, solo) | ✅ `1733eee`. `FrmrType`, `FrmrMotion`, `Constants.DesignUI`, `ThemePalette.resolve(for:surface:contrast:)` roles (darkroom / paper light / paper dark, each with Increase Contrast), upgraded `frmrGlass` + `FrmrGlassContainer` + `frmrPrimaryButtonStyle`, adaptive tab tint, 44pt floor, role-contrast tests. Lead check: 303 unit tests pass, guard clean. Backend UI shards moved to `frmr-ui-4…6`. |
| Parallel round, **2 agents (user, 2026-10-22: fewer merge conflicts)**:<br>• **Frontend on Opus 5.5** (user's choice): all screens. That is A's scope (camera, editor + Exposure tool, prompt, strip) plus B's (Library/Roll, viewers, Settings, TipKit).<br>• **Backend on Sonnet:** `FilmLook.exposure` + pipeline, stockPreviews, chromePlacement, Library accessors, haptics, swatches, edit-after-shot setting.<br>Both work in the main folder on `v5.2-makeover` with disjoint files (views/components/UI constants vs models/view models/pipeline/non-UI constants), so no worktrees. | **In progress** (started 2026-10-22). The lead fixed the API contract up front (exposure, previews, `ChromePlacement`, edit-after-shot, `HapticEvent`, `FilmSwatch`, Library accessors, `linkedEntryCountIfKnown`). |
| QA accessibility pass | Queued |
| Backend (Sonnet) | ✅ All contract items.<br>• **Exposure** is baked into the film cube (part of the cache key; the cube cache raised 8 → 16), with plain gain for stock Off; it flows to strips via `StripCustomization.exposure`.<br>• **Previews:** two caches.<br>• **`chromePlacement`:** `.below` on iPhone 13 and later, `.overlay` on 12 mini / SE; the stack height of 172 still needs tuning by the frontend.<br>• **`captureForPhoto(context:)`:** edit-after-each-shot off saves straight to the Roll.<br>• **Haptics:** `HapticEvent` + Core Haptics film advance; `FilmSwatch`; Library accessors; `linkedEntryCountIfKnown`.<br>• About 30 tests; **341 unit pass** (agent-reported); `docs/film-simulation.md` updated.<br>• Its PhotoModeUITests run failed 3 tests while the frontend's views were mid-change; to be re-checked after the frontend finishes. |
| Frontend (Opus 5.5) | ✅ `c828ad7`.<br>**Done:** M1 contrast, M3 Dynamic Type (49 → 8 fixed sizes, glyphs only), M4 44pt (frame assertions in UI tests), M5 + F-EXP editor (Exposure first, stock/print thumbnail rows, value rings, compare button + VoiceOver action), M6/S5 contact-sheet Roll, M7 Reduce Motion/Transparency, S1 camera below/overlay with swatch dial, value-on-button WB/EV and HUD, S2 mini-strip slots sheet, S3 strip screen sheet with one "Keep strip", S4 prompt redesign, S6 Settings Form (Default look page, Edit after each shot, Film-advance haptics), C1 TipKit (coach views deleted), C2 developing reveal; BUG-V51-02/03 frontend parts.<br>**Deferred:** ⋯ menu, slot reorder, 4/4 shutter morph, C3–C6, Default look sample preview, prompt matched transition.<br>**Lead check:** 341 unit pass, guard clean (TipKit added to the allowlist). Screenshots in `qa/screenshots/v5.2/{before,after}/`. |
| Cleanup round (backend Sonnet + frontend Opus) | Done (2026-10-23).<br>• **Backend:** onboarding/coach backend removed; `stripProgressBadge`, `didSaveToCameraRoll`, `hasEntriesToday`, `Tab` label; `belowChromeStackHeight` 170.<br>• **Frontend:** status bar follows the user's appearance choice only (never per tab); the camera hides it, like the system Camera; darkroom covers stay dark. Strip Download shows Saved. Print-label truncation not re-checked on screen.<br>• Lead check: 332 unit tests, all UI tests pass, guard clean. User checking on device. |
| QA accessibility pass (Sonnet) | Deferred; the user is checking on device first |
