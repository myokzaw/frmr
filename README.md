# frmr

A minimalist photography journal for iOS with a real film look. Take a photo on a film stock, get a written prompt, write a short reflection, and collect entries into photobooth-style strips.

The film look is built from how film actually works, not from filters: each stock has its own tone curve per colour layer, is printed onto a print stock, and picks up the physical artefacts of film (halation around highlights, grain that follows exposure, a soft bloom and the occasional light leak). Everything is rendered on the device.

Everything is intentional and user-initiated:

- **Offline.** No network calls, no sync, no analytics.
- **No AI.** Prompts come from a static list in the app.
- **No automatic actions.** Saving to the camera roll, generating a strip and sharing each need an explicit tap.
- **Custom camera.** `AVCaptureSession` + `AVCapturePhotoOutput` with RAW capture. No system image picker for capture.

## What it does

- **Camera** with two modes: a single diary shot, or a four-shot film strip.
  - Tap to focus and expose, swipe for exposure compensation, pinch to zoom.
  - White balance presets, front/back flip and back-lens selection.
  - Choose a film stock right on the camera screen (OFF, D200, P400, C500, S100, M400, M3.2K), with the viewfinder showing that stock's colour and tone live.
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
  - **Bloom and light leaks.** An optional soft diffusion glow, and warm leaks at the frame edge.
  - Effects are seeded per frame, so the same strip always renders identically.
- **Diary.** Each photo gets a prompt and a short written response.
  - After you take the photo, a review screen lets you change its stock before pressing **OK** (bottom left) for the prompt, or **Retake** (bottom right). The original photo is kept, and the stock is applied when it's shown. A download button at the top right saves the full-resolution photo with its film look to the camera roll without starting a diary entry.
- **Strips.** Four frames compile into a photobooth-style strip: 4:5 frames close together in a thin border on warm off-white or near-black photo paper, a one-line caption under each frame, and the date.
  - Choose a stock, a print, effects and black and white on the strip screen.
  - Strips render each frame "As shot" in its own stock, or override all four with one.
  - Strips live in a library and export to the camera roll on request.
- **Settings.** Appearance, strip defaults (stock, print, effects, B&W), and a replay of the first-run walkthrough.

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
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version, in plain language |
| [CLAUDE.md](CLAUDE.md) | Engineering rules, hard constraints, agent team and file ownership |
| [project.md](project.md) | Full product specification and v1/v2 implementation status |
| [frmr-v2-spec.md](frmr-v2-spec.md) | v2 features and build status |
| [frmr-v3-spec.md](frmr-v3-spec.md) | v3 features, build status, and the post-v3 rotate-in-place rework with v4 carry-forward |
| [frmr-v4-spec.md](frmr-v4-spec.md) | v4 film pipeline: orientation fix, characteristic curves, print stage, halation, grain, bloom and light leak. Part 2: plain white/black strip, film stock on the camera with live preview, diary review step, per-photo stocks with strip override |

## Status

- **v1–v3:** implemented.
- **v4 Part 1, the film pipeline:** implemented and tested (138 unit tests, zero warnings). It covers the orientation fix, characteristic curves, the print stage, halation, grain v2, bloom, light leaks, and the stock, print and effect controls.
- **v4 Part 2, film at capture:** implemented and tested on the simulator (QA: 215 unit tests, 6 UI tests, Debug and Release builds). It covers the camera film stock with live preview, the diary review step with Download, per-photo stocks with "As shot" strips, the booth strip, the shadow fix and stock calibration against real film.
- **Unverified on a physical device:** the live viewfinder (frame rate, heat, mirroring, tap alignment), real capture → review → Download to the camera roll, the film look on real captures, render timings, and capture orientation. The checklist is in `frmr-v4-spec.md`.

See `frmr-v4-spec.md` §Implementation status and [CHANGELOG.md](CHANGELOG.md).

## Working on it

The repo includes a three-agent setup for Claude Code (`.claude/agents/`): frontend, backend and QA, with a file ownership map in `CLAUDE.md`. `scripts/frmr-guard.sh --all` checks the hard constraints (no network, no Combine, no third-party imports and similar) and runs as a hook on every agent edit.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
