# Changelog

What changed in each version of frmr, in plain language. Technical detail, decisions and test results live in the matching `frmr-v*-spec.md`.

## v5.2.1 — fixes (in progress)

- **Fixed:** on the diary prompt screen, tapping the empty space under the prompt now brings up the keyboard. Before, only the small text box itself responded.
- **Fixed:** the app no longer freezes and quits when the keyboard opens on the diary prompt screen.

## v5.2 — UI makeover (branch `v5.2-makeover`)

**Status:** built and tested on the simulator (2026-10-23): 332 unit tests and all UI tests pass. Device checks in progress; the QA accessibility pass is deferred. Spec: `frmr-v5.2-spec.md`; research behind it: `research/v5.2-ui-makeover.md`.

- **Exposure in the editor.** A new first tool: −2 to +2 stops in ⅓-stop steps, applied before the film look. Bright areas roll off like overexposed film instead of clipping, and the setting is saved with the photo.
- **Camera.**
  - On tall phones the dial and shutter sit below a 3:4 viewfinder, so nothing covers the image.
  - The dial shows a colour swatch for each stock.
  - White balance and exposure show their values when you change them, and a brief flash shows the new setting.
  - The status bar is hidden over the viewfinder, like the system Camera. Other screens follow your Appearance setting, so the status bar stays readable in light mode.
- **Film strip.** The four slots live in a small strip next to the shutter. Tap it for gallery, Roll, undo and Generate.
- **Editor.**
  - Film and Print show small previews of your photo in each option.
  - Effect icons show a ring for their strength.
  - Compare is a button.
  - A fresh photo fades in as it "develops".
- **Strip screen.** One "Keep strip" button, with Share and Download as icons.
- **Prompt screen.** Redesigned around the photo and your words.
- **Library.**
  - The Roll is a contact sheet grouped by day.
  - Entries show what you wrote first.
  - Strips sit in two columns.
  - Empty screens use the system style.
- **Settings.** A grouped list with a Default look page, plus two new switches: **Edit after each shot** (turn it off to keep shooting and edit later) and **Film-advance haptics**.
- **Tips instead of a tour.** The walkthrough is replaced by short tips that point at the real controls.
- **Accessibility everywhere.**
  - Text scales with Dynamic Type.
  - Every control is at least 44pt.
  - High-contrast colours, with Increase Contrast variants.
  - Reduce Motion and Reduce Transparency are respected.
- **Shared design system.** One set of type, spacing, colour, glass and motion values (`project.md` §5a).

**Not yet checked on a real iPhone:**
- the shutter's film-advance haptic;
- the new camera layout on different phone sizes;
- the Liquid Glass look and the blur on older iOS;
- the tips appearing over the real camera permission prompt.

## v5.1 — Diary from the editor, and a modern look (branch `v5-photo-camera`)

**Status:** built and tested on the simulator, and QA-verified (2026-10-21); device checks outstanding. Spec: `frmr-v5.1-spec.md`.

- **Diary is part of taking a photo.** The mode switch is now Photo / Film strip.
  - After a shot, **Continue to diary** (next to Save to roll) saves the photo to your Roll and opens the prompt.
  - The entry is linked to that photo, so re-editing the photo updates the entry.
  - Older entries are unchanged.
- **One camera for both modes.** Film strip uses the same camera as Photo:
  - a glass mode switch, and white balance and exposure buttons at the top;
  - the slim stock dial and the shutter.
  - It adds four slots, gallery / Roll / undo buttons, and a Generate button once a slot is filled.
- **A simpler editor.**
  - Icon buttons for discard, retake and download.
  - A row of tools (Film, Print, Halation, Haze, Light leak, Grain, Vignette) with one tick-mark scrubber that clicks every 10%.
  - The photo stays large.
- **A modern look everywhere.**
  - Glass controls (Liquid Glass on iOS 26, frosted on older iOS) and amber primary buttons with dark text.
  - A Library with Roll / Entries / Strips. Roll photos with a diary entry show a book badge. Entries show what you wrote first. Strips appear in two columns.
  - Full-screen photo and strip viewers, and a refreshed Settings screen and walkthrough.
- **Safer deletes.** Deleting a photo that has a diary entry asks whether to delete both or keep the entry. Clear roll keeps entries by default.
- **Roll photos in strips keep their full look.** Print and effects carry over, not just the stock.
- **Accessibility.**
  - Higher-contrast colours that pass accessibility contrast checks, and every control at least 44pt.
  - Respects Reduce Motion and Reduce Transparency.
- **Faster development.**
  - Each agent has its own simulator.
  - One test script (`scripts/test.sh`) builds once and re-runs a suite in about 6 s; the full unit run takes under a minute.
  - UI tests run across three simulators at once, and the constants are split into one file per section.

**Not yet checked on a real iPhone:**
- the new camera chrome in landscape;
- the haptics;
- the Liquid Glass look and the blur fallback on older iOS;
- large text sizes.

## v5 — The camera is the main feature (branch `v5-photo-camera`)

**Status:** built and tested on the simulator (2026-10-21); device checks outstanding. Spec: `frmr-v5-spec.md`.

- **Opens on the camera.** The app now opens straight into a Photo camera. Diary and Film strip are options in the mode switch (camera, book, film icons).
- **Stock dial.** Swipe a dial of the seven stocks above the shutter; the viewfinder shows the look live.
- **White balance and exposure.** Presets plus Kelvin and tint sliders, and exposure compensation in ⅓-stop steps (the swipe gesture still works). Only one panel opens at a time.
- **Edit after every shot.**
  - Change the stock, the print, black and white, and each effect's strength.
  - Hold the photo to compare with the original.
  - Download to Photos, or Save to roll.
- **Effect sliders everywhere.** Halation, Haze (the old bloom), Light leak, Grain and a new Vignette are 0–150% sliders on the editor, strip screen, diary review and Settings. 0% is the same as off, and existing photos and strips look exactly as before.
- **Roll.** A new first tab in the Library.
  - Every saved photo keeps its original plus its look, so it can be re-edited.
  - Export to Photos, delete, or pick up to four photos for a strip.
  - Settings has a separate "Clear roll".
- **Smaller changes.**
  - The last photo's thumbnail sits beside the shutter.
  - The walkthrough describes the camera as the main screen.
  - The unused "Remember white balance" setting is gone.
  - Dragging a strip slider no longer buzzes repeatedly.
- **Docs.** New `docs/film-simulation.md` explains how the film look works for anyone (or any agent) changing it. New `docs/testing.md` maps where tests live.
- **Leaner tests.** Repeated tests were merged into parameterised ones. The test file was split by theme, and the Xcode template UI tests were removed. 310 → 283 unit tests (151 parameterised cases) and 14 → 11 UI tests, with every removed test mapped to the one that now covers it.

**Not yet checked on a real iPhone:**
- a real capture flowing into the editor;
- white balance and exposure on the real camera;
- the dial's haptics;
- export to Photos;
- landscape layouts.

## v4 — Film pipeline (released on `main`)

### Part 2: Film at capture — done on the simulator (2026-10-21), device checks outstanding

Spec: `frmr-v4-spec.md` §Part 2 (F8–F15).

- **Plain strip (F8).** Strips use a white or black background only. Sprocket holes, frame numbers and the sideways edge date are removed. Captions and the bottom date stay. A saved "cream" background becomes white.
- **Film stock on the camera (F9).** A Film control on the camera screen in both Diary and Film strip modes. The viewfinder shows the stock's colour and tone live; grain and other effects appear on the captured photo.
- **Diary review step (F10).** After taking a diary photo you see it in its stock, can change the stock, then press **OK** (bottom left) to get the prompt, or **Retake** (bottom right).
- **Per-photo stock (F11).** Each diary entry and strip shot remembers its stock. The original photo is kept unchanged and the look is applied when shown. Older entries show as Off.
- **"As shot" strips (F12).** A strip renders each frame in its own stock by default, or one chosen stock can override all four.
- **Download from the review screen (F13).** A download button at the top right of the diary review screen saves the photo, with its full film look, to the camera roll. It doesn't create a diary entry; you can still press OK afterwards to write one.
- **Truer shadows.** Real photos showed every stock turning blacks grey and flattening dark scenes. Blacks are now deep on Lab, Cinema and Slide prints, and dark detail keeps its separation. Matte paper stays intentionally faded.
- **Stocks tuned against real film (F14).** Compared against real scans of the film families each stock is modelled on:
  - Daylight 200 is warmer and punchier.
  - Portrait 400 is softer and gentler.
  - Cine 500T has teal shadows.
  - Slide 100 is the most saturated stock.
  - Mono 3200 has finer grain.
- **Booth-style strip (F15).** Frames are slightly taller than wide and sit close together inside a thin border, on warm off-white or near-black photo paper with a faint texture. Captions stay under each frame.

**Quality (Part 2).** QA verified Part 2 on the simulator: 215 unit tests, 6 UI tests, and Debug and Release builds with zero warnings. Coverage includes mixed-stock "As shot" strips staying upright and identical on re-render, Download keeping photos upright at full resolution, and each photo's stock carrying through to its strip.

**Not yet checked on a real iPhone:**
- the live viewfinder (smoothness, heat, mirroring, tap-to-focus alignment);
- a real capture → review → Download to the camera roll;
- the Film chip in landscape;
- the booth strip on a real display.

### Part 1: Film look — done (2026-10-20)

Spec: `frmr-v4-spec.md` F0–F7.

- **Fixed: photos turned sideways in strips (F0).** Photos taken in landscape came out rotated as soon as grain or black and white was switched on. They now stay upright with every stock and effect.
- **Faster strips (F1).** Photos are resized to their strip slot before the film look is applied. Rendering a strip of four 12 MP photos dropped from about 2 s to 0.1 s on the simulator.
- **Real film tone and colour (F2, F3).**
  - Each stock has its own response curve per colour layer.
  - The negative is printed on a print stock (Lab, Cinema, Matte, or Projection for slide film), balanced so neutral grey stays neutral.
  - White prints near white.
- **Halation (F4).** A warm glow around bright highlights, strongest on Cine 500T.
- **Grain v2 (F5).** Two grain sizes, scaled to film speed and following the film's density. Colour stocks get slightly coloured grain. Grain never shifts overall brightness.
- **Bloom and light leaks (F6).** An optional soft glow and warm edge leaks. Both are off by default and only ever brighten.
- **New controls (F7).** Six stocks replace the old ISO 100/400/3200 options:
  - **Stocks:** Daylight 200, Portrait 400, Cine 500T, Slide 100, Mono 400 and Mono 3200.
  - **Strip screen:** stock, print and effect controls, plus Black & white, which is locked on for mono stocks.
  - **Settings:** matching strip defaults.
  - **Old settings:** saved ISO values move to the nearest new stock automatically.
- **Consistent results.** Effects are seeded per frame, so the same strip always renders identically, and each frame in a multi-strip render gets its own grain.
- **Quality.** 138 unit tests, including an orientation check across every stock and effect combination, plus a UI test that drives the strip screen. Zero compiler warnings.

**Not yet checked on a real iPhone:** the film look on real photos, render speed on a phone, and landscape captures through the strip.

## v3 — Rotate-in-place camera and first-run walkthrough

See `frmr-v3-spec.md`. Camera controls rotate individually under a portrait lock. A first-run walkthrough explains the tabs and can be replayed from Settings. Captures are saved upright in any orientation.

## v2 — Camera feel and film grain

See `frmr-v2-spec.md`. Tap to focus and expose, swipe for exposure, pinch to zoom, luminosity-weighted grain with ISO film stocks, animated viewfinder grain, sprocket holes and frame numbers, and haptics.

## v1 — Photo journal

See `project.md` §14. Custom RAW camera, prompts and diary entries, four-frame strips, photobooth mode, library and settings.
