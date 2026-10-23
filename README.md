# frmr

**A film camera for your iPhone. Shoot on film stocks, fine-tune every frame, and keep a quiet photo diary.**

frmr makes your photos look like film because it works like film. Each stock has its own colour response and is printed onto real print paper, with the glow, grain and light leaks of a physical roll. Everything happens on your phone. There are no accounts, no internet and no AI.

## Features

### Shoot on film
- **Six film stocks, live in the viewfinder.** Swipe the stock dial and see the look before you take the shot.
  - **Daylight 200:** warm, everyday colour.
  - **Portrait 400:** soft, gentle skin tones.
  - **Cine 500T:** cool tungsten cinema film with a red glow around lights.
  - **Slide 100:** punchy, saturated, deep blacks.
  - **Mono 400:** classic black and white.
  - **Mono 3200:** hard contrast and heavy grain.
- **A real camera.** It captures RAW photos. Tap to focus, pinch to zoom, swipe to change exposure, and set white balance with presets or Kelvin and tint.
- **Composition grid.** Thirds, square or golden-ratio lines, set in Settings.
- **Built for one hand.** On tall iPhones the dial and shutter sit below the viewfinder, so nothing covers your shot. The controls turn upright as you rotate the phone, like the Camera app.

### Make every frame yours
- **Edit right after the shot, or later.** Change the exposure (±2 stops), the stock, the print paper or black and white. Small previews show your own photo in each option.
- **Physical film effects.** Halation, Haze, Light leak, Grain and Vignette, each from 0 to 150%.
- **Compare.** Hold to see the original.
- **Nothing is lost.** Your Roll keeps every original, so you can re-edit any photo at any time.

### Keep a photo diary
- **Continue to diary.** Answer a short, thoughtful prompt about a photo, right after you take it or later from your Roll.
- Each entry stays linked to its photo. If you re-edit the photo, the entry updates too.

### Make photo strips
- **Film strip mode.** Shoot or pick four frames for a photobooth-style strip on white or black photo paper, with captions and the date.
- Use one stock for every frame, or keep each photo as you shot it.

### Private by design
- **Fully offline:** no accounts, no sync, no analytics, no network.
- **No AI.** Your words and photos stay yours.
- **Nothing happens without you.** Saving, sharing and exporting each need a tap.
- **Made for everyone.** It supports Dynamic Type, VoiceOver, Increase Contrast, Reduce Motion and Reduce Transparency, with Liquid Glass on iOS 26.

## How the film look works

- **Characteristic curves.** The red, green and blue layers of each stock each respond to light separately. Each has a soft toe in the shadows and a rolled-off shoulder in the highlights.
- **Print stage.** The negative is printed on Lab, Cinema or Matte paper, and slide film is projected. The print is balanced so neutral grey stays neutral.
- **Exposure first.** Exposure is applied before the film curve, so bright areas roll off like overexposed film instead of clipping.
- **Effects.**
  - Halation: light bouncing back through the film.
  - Grain: two sizes, following film speed and density.
  - Haze, light leaks and vignette.
  - Each effect is seeded per frame, so a strip renders the same every time.

Full detail: [docs/film-simulation.md](docs/film-simulation.md).

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
  Features/       Camera, PhotoEdit, Roll, Diary, Strip, Photobooth, Library, Settings
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
| [frmr-v5.2-spec.md](frmr-v5.2-spec.md) | v5.2 UI makeover: Exposure, design tokens, camera layout, editor previews, contact-sheet Roll, TipKit, accessibility |
| [research/v5.2-ui-makeover.md](research/v5.2-ui-makeover.md) | Design audit and research behind v5.2 |
| [frmr-v5-spec.md](frmr-v5-spec.md) | v5: the photo camera as the main screen (stock dial, white balance and exposure, edit after every shot, effect sliders, Roll) |
| [frmr-v4-spec.md](frmr-v4-spec.md) | v4 film pipeline: orientation fix, characteristic curves, print stage, halation, grain, bloom and light leak. Part 2: plain white/black strip, film stock on the camera with live preview, diary review step, per-photo stocks with strip override |

## Status

- **v5.2 (UI makeover) is on `main`.** It includes v4 (film pipeline), v5 (camera first, the Roll), v5.1 (diary from the editor, one camera for both modes) and v5.2 (Exposure, design system, accessibility).
- **Tests:** 332 unit tests and all UI tests pass on the simulator.
- **Physical device:** checks are in progress. The open checklists are in the v4, v5 and v5.2 specs.

See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Working on it

The repo includes a three-agent setup for Claude Code (`.claude/agents/`): frontend, backend and QA, with a file ownership map in `CLAUDE.md`. `scripts/frmr-guard.sh --all` checks the hard constraints (no network, no Combine, no third-party imports and similar) and runs as a hook on every agent edit.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
