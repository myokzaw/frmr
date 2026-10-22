# frmr

A minimalist film camera for iOS. Shoot on a film stock, fine-tune the look after every shot, and keep your photos in a re-editable roll. Any photo can become a **diary** entry with a reflective prompt, and the **Film strip** mode makes photobooth-style strips.

The film look is built from how film actually works, not from filters: each stock has its own tone curve per colour layer, is printed onto a print stock, and picks up the physical artefacts of film (halation around highlights, grain that follows exposure, a soft bloom and the occasional light leak). Everything is rendered on the device.

Everything is intentional and user-initiated:

- **Offline.** No network calls, no sync, no analytics.
- **No AI.** Prompts come from a static list in the app.
- **No automatic actions.** Saving to the camera roll, generating a strip and sharing each need an explicit tap.
- **Custom camera.** `AVCaptureSession` + `AVCapturePhotoOutput` with RAW capture. No system image picker for capture.

## What it does

- **Camera (the main screen).** The app opens straight into Photo mode.
  - **Stock dial:** swipe it above the shutter to pick a stock (OFF, D200, P400, C500, S100, M400, M3.2K). The viewfinder shows that stock's colour and tone live.
  - **White balance:** presets, plus fine-tune Kelvin and tint sliders.
  - **Exposure compensation:** in ⅓-stop steps, from a chip or by swiping on the viewfinder.
  - Tap to focus and expose, pinch to zoom, front/back flip and back-lens selection.
  - **Mode switch:** Photo (default) and Film strip. Both use the same camera controls.
- **Edit after every shot.**
  - **Film and Print:** change the stock, the print paper, or switch to black and white.
  - **Effects:** a tool row with one scrubber (0–150%) for Halation, Haze, Light leak, Grain and Vignette, with reset.
  - Hold the photo to compare with the original.
  - **Download** saves the full-resolution film photo to Photos; **Save to roll** keeps it in the app; **Continue to diary** saves it and opens a reflective prompt.
- **Roll.** Every photo you save keeps its original plus its look, so you can re-edit it any time.
  - Export to Photos, delete, or pick up to four photos to make a strip.
- **Film stocks.** Six looks plus Off:
  - **Daylight 200:** warm, everyday colour.
  - **Portrait 400:** soft, low contrast, gentle skin tones.
  - **Cine 500T:** cool tungsten cinema film with strong halation.
  - **Slide 100:** punchy, saturated, deep blacks.
  - **Mono 400:** classic black and white.
  - **Mono 3200:** hard contrast and heavy grain.
- **How the film look is made:**
  - **Characteristic curves.** Each stock's red, green and blue layers respond to light separately, with a soft toe in the shadows and a rolled-off shoulder in the highlights. Their differences give each stock its colour character.
  - **Print stage.** The negative is printed on Lab print, Cinema print or Matte paper; slide film is projected. The look is the two curves combined, balanced so neutral grey stays neutral.
  - **Halation.** A warm red-orange glow around bright highlights, as light bounces back through the film.
  - **Grain.** Two sizes of grain, scaled to film speed and strongest where the film is densest. Colour stocks get slightly coloured grain.
  - **Haze, light leaks and vignette.** A soft diffusion glow (Haze), warm leaks at the frame edge and corner darkening, each with its own strength slider.
  - Effects are seeded per frame, so the same strip always renders identically.
- **Diary.** From the editor, **Continue to diary** gives a photo a prompt and a short written response. The entry stays linked to the photo in your Roll.
- **Film strips (mode).** Four frames compile into a photobooth-style strip: 4:5 frames close together in a thin border on warm off-white or near-black photo paper, a one-line caption under each frame, and the date.
  - Choose a stock, a print, effect strengths and black and white on the strip screen. Frames can come from the camera, your phone's gallery or your Roll.
  - Strips render each frame "As shot" in its own stock, or override all four with one.
  - Strips live in a library and export to the camera roll on request.
- **Settings.** Appearance, strip defaults (stock, print, effect strengths, B&W), Clear diary, Clear roll, and a replay of the first-run walkthrough.

On the camera screen the interface is locked to portrait. Controls keep their positions and rotate individually, in place, to stay upright as the phone turns, like the system Camera app.

## Requirements

- Xcode with the iOS 17+ SDK
- An iOS 17+ device or simulator
- A physical device for anything involving the camera, orientation sensor or haptics. The simulator has none of these.

No third-party dependencies.

## Build and test

```sh
xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination 'platform=iOS Simulator,id=<simulator-id>' build

xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  -only-testing:frmrTests test
```

List simulators with `xcrun simctl list devices available`. Use the `id=` form, because several runtimes can share a device name.

## Stack

Swift 5.9+, SwiftUI, `@Observable`, SwiftData, AVFoundation, CoreImage, PhotosUI, `PHPhotoLibrary`, async/await.

## Project layout

```
frmr/
  App/            app entry, tab root
  Features/       Camera, Diary, Strip, Photobooth, Library, Settings, Onboarding
  Models/         SwiftData models
  Shared/         components, extensions, Constants.swift
frmrTests/        unit and acceptance tests
frmrUITests/      UI tests
scripts/          frmr-guard.sh constraint checker
qa/bugs/          QA bug reports
```

## Documentation

| File | Contents |
|---|---|
| [docs/testing.md](docs/testing.md) | Test layout by theme, the parameterised invariant tests, gated calibration tools, how to run, and the "search before adding a test" rule |
| [docs/film-simulation.md](docs/film-simulation.md) | How the film simulation works end to end: pipeline order, the film maths, effects, seeds, invariants, and how to tune or extend it |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version, in plain language |
| [CLAUDE.md](CLAUDE.md) | Engineering rules, hard constraints, agent team and file ownership |
| [project.md](project.md) | Full product specification and v1/v2 implementation status |
| [frmr-v2-spec.md](frmr-v2-spec.md) | v2 features and build status |
| [frmr-v3-spec.md](frmr-v3-spec.md) | v3 features, build status, and the post-v3 rotate-in-place rework with v4 carry-forward |
| [frmr-v5-spec.md](frmr-v5-spec.md) | v5: the photo camera as the main screen (stock dial, white balance and exposure, edit after every shot, effect sliders, Roll) |
| [frmr-v4-spec.md](frmr-v4-spec.md) | v4 film pipeline: orientation fix, characteristic curves, print stage, halation, grain, bloom and light leak. Part 2: plain white/black strip, film stock on the camera with live preview, diary review step, per-photo stocks with strip override |

## Status

- **v1–v3:** implemented.
- **v4, film pipeline and film at capture:** released on `main`.
- **v5 and v5.1, the photo camera as the main feature:** built and tested on the simulator, on branch `v5-photo-camera`. v5.1 adds the diary from the editor, one camera for Photo and Film strip, and a modern glass UI.
  - Photo mode at launch, the stock dial, white balance and exposure controls, the editor after every shot, effect strength sliders everywhere, and the Roll.
  - Tests were consolidated: 283 unit tests (151 parameterised cases) and 11 UI tests, with no coverage lost (`qa/test-consolidation/mapping.md`).
- **Unverified on a physical device:** the live viewfinder, real capture → editor → Download, white balance and exposure on the real camera, the dial haptics, export to Photos, landscape layouts, and the film look on real captures. Checklists are in `frmr-v4-spec.md` and `frmr-v5-spec.md`.

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Working on it

The repo includes a three-agent setup for Claude Code (`.claude/agents/`): frontend, backend and QA, with a file ownership map in `CLAUDE.md`. `scripts/frmr-guard.sh --all` checks the hard constraints (no network, no Combine, no third-party imports and similar) and runs as a hook on every agent edit.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
