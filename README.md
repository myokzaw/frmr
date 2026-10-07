# frmr

A minimalist photography journal for iOS. Take a photo, get a written prompt, write a short reflection, and collect entries into photobooth-style film strips.

Everything is intentional and user-initiated:

- **Offline.** No network calls, no sync, no analytics.
- **No AI.** Prompts come from a static list in the app.
- **No automatic actions.** Saving to the camera roll, generating a strip and sharing each need an explicit tap.
- **Custom camera.** `AVCaptureSession` + `AVCapturePhotoOutput` with RAW capture. No system image picker for capture.

## What it does

- **Camera** with two modes: a single diary shot, or a four-shot film strip.
  - Tap to focus and expose, swipe for exposure compensation, pinch to zoom.
  - White balance presets, front/back flip and back-lens selection.
  - Film stock looks with luminosity-weighted grain.
- **Diary.** Each photo gets a prompt and a short written response.
- **Film strips.** Four frames compile into a strip with sprocket holes and frame numbers. Strips live in a library and export to the camera roll on request.
- **Settings.** Including a replay of the first-run walkthrough.

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
| [CLAUDE.md](CLAUDE.md) | Engineering rules, hard constraints, agent team and file ownership |
| [project.md](project.md) | Full product specification and v1/v2 implementation status |
| [frmr-v2-spec.md](frmr-v2-spec.md) | v2 features and build status |
| [frmr-v3-spec.md](frmr-v3-spec.md) | v3 features, build status, and the post-v3 rotate-in-place rework with v4 carry-forward |

## Status

v1, v2 and v3 are implemented. The camera chrome was reworked after v3 to rotate in place under a portrait lock. Rotation direction, upside-down behaviour and capture orientation are still unverified on a physical device. See the end of `frmr-v3-spec.md` for the checklist and open items.

## Working on it

The repo includes a three-agent setup for Claude Code (`.claude/agents/`): frontend, backend and QA, with a file ownership map in `CLAUDE.md`. `scripts/frmr-guard.sh --all` checks the hard constraints (no network, no Combine, no third-party imports and similar) and runs as a hook on every agent edit.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
