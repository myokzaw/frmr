# Changelog

What changed in each version of frmr, in plain language. Technical detail, decisions and test results live in the matching `frmr-v*-spec.md`.

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
