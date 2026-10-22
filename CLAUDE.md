# CLAUDE.md

You are a senior iOS engineer building a minimalist photography journaling app. This file is your complete operating context. Read it fully before writing any code or making any decisions.

## What this app is

A journaling app where users take photos on a chosen film stock, receive a written prompt, write a short reflection, and collect entries into photobooth-style strips. Since v4 the film look is physically based: per-layer characteristic curves, a negative → print chain, halation, exposure-dependent grain, bloom and light leaks, all on device (`frmr-v4-spec.md`). No AI. No network. No automation. Every action is user-initiated and intentional.

## Hard constraints — never violate these

- **No network calls.** This app is 100% offline. No APIs, no sync, no analytics, no crash reporting that phones home.
- **No AI anywhere.** Not for prompts, not for captions, not for suggestions. The prompt bank is a static Swift array.
- **No automatic actions.** Saving to camera roll, generating a strip, sharing — all require an explicit user tap.
- **Custom camera only.** Use AVCaptureSession + AVCapturePhotoOutput with RAW capture. Never use UIImagePickerController or PHPickerViewController for capture.
- **No third-party dependencies** unless a native API literally cannot do the job. If you think you need one, flag it and wait for approval.

## Stack

| Concern | Decision |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI, iOS 17 minimum |
| State | `@Observable` (Swift Observation framework) — not ObservableObject |
| Persistence | SwiftData |
| Camera capture | AVFoundation — AVCaptureSession, AVCapturePhotoOutput |
| Image processing | CoreImage pipeline (see project.md §7) |
| Gallery selection | PhotosPicker (PhotosUI) |
| Saving to library | PHPhotoLibrary |
| Async | async/await — no Combine, no completion handlers |

## Project layout

```
App/
  AppEntry.swift
  ContentView.swift          # TabView root, nothing else

Features/
  Camera/
    CameraView.swift
    CameraViewModel.swift
    CaptureSession.swift     # AVCaptureSession wrapper
    ImageProcessor.swift     # CoreImage pipeline
    WhiteBalanceControl.swift
  Diary/
    DiaryView.swift
    DiaryViewModel.swift
    EntryEditorView.swift    # prompt display + text input
    EntryDetailView.swift    # full-screen photo + prompt + response viewer
    PromptBank.swift         # static [String] array, zero logic
  Strip/
    StripView.swift
    StripViewModel.swift
    StripGenerator.swift     # layout + rendering
  Photobooth/
    PhotoboothView.swift
    PhotoboothViewModel.swift
  Library/
    LibraryView.swift
    LibraryViewModel.swift
    StripDetailView.swift    # full-screen strip viewer
  Settings/
    SettingsView.swift

Models/
  DiaryEntry.swift
  DailyStrip.swift
  StripCustomization.swift

Shared/
  Components/                # reusable SwiftUI views
  Extensions/                # Color palette, Date formatting, FileManager paths, PHPhotoLibrary saving
  Constants.swift            # all magic numbers live here
```

## Code rules

**Views are dumb.** No business logic in SwiftUI views. If you find yourself writing a conditional or a data transformation inside a view body, move it to the ViewModel.

**No force-unwraps in production paths.** Use `guard let`, `if let`, or `Result`. The only acceptable `!` is in test code.

**Errors reach the user.** Never silently catch and discard. Errors surface via a shared `AppError` state that triggers an alert. Log to console for debugging; show a human-readable message to the user.

**Constants, not magic numbers.** Every pixel value, character count, filter parameter, and timing value goes in `Constants.swift` with a descriptive name.

**Comments explain why.** If the code clearly shows what it does, don't restate it in a comment. Write a comment when the reason for a decision isn't obvious.

## Handling open decisions

Several product decisions are not yet made (see project.md §13). When you hit one:

1. Use the most conservative reasonable default.
2. Mark it in code with `// OPEN: <description of what needs deciding>`.
3. Put the value in `Constants.swift` so it's easy to change, not buried inline.
4. Finish your current task. Don't block on it.

Never invent an answer to a TBD item. Make the placeholder obvious and move on.

## Working with other agents

If you are handing off to another agent, or if you are a downstream agent receiving a handoff, use this protocol.

**Always pass both files as context.** An agent without `project.md` and `CLAUDE.md` will make wrong decisions. Don't assume the downstream agent has read any prior conversation.

**Decompose by context, not by role.** Don't split "writing" from "testing" the same feature — the test agent won't have the context it needs. Split by genuine context boundaries: independent features, separate components with clean interfaces, or verification tasks that only need the artifact and a success criterion (not the history of how it was built).

**State the current situation explicitly.** Every handoff message must include:

```
DONE:    [specific files or flows that are complete and working]
DOING:   [the exact task in flight, if any]
BLOCKED: [any OPEN: items that must be resolved before proceeding]
NEXT:    [the specific task for the receiving agent]
```

**Verification agents work best when the task is blackboxable.** If a verifier only needs to run tests and report results, it doesn't need implementation context. Give it the artifact and the success criteria, nothing more.

### Handoff template

```
You are working on [FEATURE] in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md  — engineering rules and constraints
2. project.md — full product specification

Situation:
  DONE:    [list]
  DOING:   [current task or "nothing"]
  BLOCKED: [open decisions blocking this work, or "none"]
  NEXT:    [your specific task]

Deliverable: [exactly what to produce — file, diff, test results, etc.]

Do not add dependencies. Do not make network calls. Do not resolve OPEN: items by guessing — flag them and use the placeholder pattern.
```

## Current build status (2026-07-31)

**v5.2 on branch `v5.2-makeover` (2026-10-22): UI makeover.** Read **project.md §5a (design tokens)** before any UI work.
- **Use the tokens:** `Font.frmr*`, `Constants.DesignUI`, `ThemePalette.resolve(for:surface:contrast:)`, `frmrGlass`, `frmrPrimaryButtonStyle`, `FrmrMotion`. No fixed font sizes and no raw hex.
- **New pieces:** `FilmLook.exposure` (in the film cube), `ChromePlacement`, `HapticEvent` / `Haptics.play`, `FilmSwatch`, editor stock/print previews, and TipKit tips (`FrmrTips.swift`). The old coach-mark walkthrough and `Features/Onboarding` are gone.
- **Agents:** the user prefers 2 per round (one frontend, one backend).

**v5 + v5.1 on branch `v5-photo-camera` (2026-10-21); simulator-verified, device checks outstanding.** The **camera is the main feature**: the app launches in Photo mode, and the modes are Photo and Film strip (`CameraViewModel.Mode` = `.photo`/`.photobooth`), both using the same chrome (`CameraChrome.swift`). The diary is reached from the editor with **Continue to diary**: it saves to the Roll and the `DiaryEntry` links via `rollPhotoID`. UI uses glass via `frmrGlass` / `frmrAdaptiveGlass` (`GlassBackground.swift`). Constants live in `frmr/Shared/Constants/`, one file per namespace. See **frmr-v5.1-spec.md** and **frmr-v5.2-spec.md** (next).
- **Key types:**
  - `FilmLook` (stock, print, B&W, effect strengths 0…1.5, where 1 = v4 and 0 = off, pixel-identical);
  - `RollPhoto` and `RollViewModel` (non-destructive Roll);
  - `PhotoEditViewModel` / `PhotoEditView` (editor after every Photo shot);
  - `StockDial`, `CameraPanels` (white balance Kelvin/tint and ⅓-EV).
- **Every sub-agent runs on Sonnet** (`model: "sonnet"`).
- **Tests:** read `docs/testing.md` before adding one. It covers where each kind of test lives, the parameterised theme tests, and the "search before adding a test" rule.
- **The v4 notes below still apply.**

**v4 built (Parts 1 and 2, 2026-10-21); simulator-verified, device checks outstanding.** See **frmr-v4-spec.md** §Implementation status and **CHANGELOG.md**.
- **Strip pipeline:** resize to slot → B&W luminance → halation → film colour cube (per-stock colour matrix → negative curve → print → shadow toe and black/white normalisation, `Features/Camera/FilmModel.swift`) → bloom → light leak → grain. Seeded by the global frame index, so re-renders are identical.
- **`StripCustomization`:** `filmStock: FilmStock?` (nil = "As shot", each frame keeps its own stock), `printStock`, `effects`, `background` (paper white/black).
- **Film at capture (Part 2):**
  - `CameraViewModel.filmStock` drives the Film chip and the live preview (`FilmPreviewRenderer` over the preview layer, which still owns taps).
  - Diary captures go through `DiaryReviewView` / `DiaryReviewViewModel` (stock row, OK, Retake, top-right Download via `ImageProcessor.renderFullLook`) before the editor.
  - Entries store the original photo plus `filmStockRaw` and render through `FilmLookCache`.
- **Booth strip:** 4:5 frames, thin border and gaps, one-line captions, textured paper (OPEN v4-16).
- **Before touching the film look:** read `docs/film-simulation.md`, the pipeline guide covering order, maths, constants, seeds, invariants and how to tune or extend it. Keep it updated in the same change.
- **Rules:**
  - Never call `CIImage(image:)` on a photo; use `ImageProcessor.uprightCIImage(from:)`.
  - Personal test photos stay outside the repo: the gated `FilmStockSampleSheetTests` / `StripSampleRenderTests` read them via `TEST_RUNNER_FRMR_*` env vars.
  - Run unit tests with `-parallel-testing-enabled NO` (parallel simulator clones fail on this machine).

**v2 is complete.** All eight v2 features (tap-to-focus/expose, swipe exposure compensation, pinch-to-zoom, luminosity-weighted grain, film stock profiles, animated preview grain, sprocket holes + frame numbers, haptics + prompt typewriter) are implemented on top of v1. Clean build, zero warnings, 28 unit tests passing. See **frmr-v2-spec.md § "Implementation status — v2 build"** for per-feature status, the three deviations from the written spec, and what still needs a physical device (F1/F2/F3 and the haptics). **project.md §14a** summarises the API changes that affect other code — most importantly that `StripCustomization.filmGrain: Bool` is now `filmStock: FilmStock`, and that `ImageProcessor.applyStripLook` needs an `outputWidth:` whenever the result will be drawn smaller than the source.

### v1 baseline

v1 is fully scaffolded and working: all six phases (Foundation, Camera, Diary, Strip, Photobooth, Library + Settings) are implemented, the app compiles without warnings, and 11 unit tests pass (StripGenerator chunking/rendering, prompt selection, SwiftData persistence against an in-memory store). Entries and strips open in full-screen viewers (`EntryDetailView`, `StripDetailView`); archived strips can be exported to the camera roll from the viewer; the camera supports front/back flipping and back-lens selection (0.5×/1×/Tele). See **project.md §14** for the per-feature file map, the post-build change log (capture-settings crash fix, viewers, persistence tests, strip export, camera switching, cover-safe error alerts), what was verified in the simulator, and the list of `// OPEN:` decisions still deferred (app name, Newsreader font bundling, WB persistence, archive soft-hide, filter tuning, prompt repeat strategy, app icon).

Notes for future agents:

- Source lives under `frmr/` (file-system-synchronized Xcode groups — files added on disk join the target automatically).
- The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Anything running off the main actor (`CaptureSession`, `ImageProcessor`, `StripGenerator`, `Constants`, palette/date extensions) is explicitly marked `nonisolated`; keep that pattern when adding pipeline code.
- Diary capture can only be exercised on a physical device; the simulator path surfaces the "no camera" `AppError` alert by design.

## Definition of done

A feature is shippable when:

- [ ] The full user flow works end to end
- [ ] Every `// OPEN:` in the feature's files has either been resolved or explicitly deferred with a note
- [ ] No force-unwraps in production paths
- [ ] All errors surface to the user
- [ ] Code compiles without warnings
- [ ] Pure logic has unit tests (StripGenerator, PromptBank selection, ImageProcessor parameter application)

## Agent team

Three project agents live in `.claude/agents/` (run recipes in `.claude/agents/README.md`). They are split along interface boundaries, not job titles, and each implementer writes the unit tests for its own pure logic.

- `frmr-frontend` — everything the user sees: views, components, chrome rotation, onboarding overlay, accessibility. Never touches AVFoundation, CoreImage or SwiftData.
- `frmr-backend` — the on-device engine: capture, image pipeline, strips, persistence, models, ViewModel logic and pure mappings.
- `frmr-qa` — black-box verifier: finds and reproduces bugs, writes acceptance/regression tests, audits constraints. Does not fix production code.

**Ownership map (hard rule — agents share one folder).**

| Area | Owner | Others |
|---|---|---|
| `ContentView.swift`, `*View.swift`, `Shared/Components/*`, `Extensions/View+*`, `Color+Palette.swift`, Coach views | frontend | read-only |
| `CaptureSession`, `ImageProcessor`, `StripGenerator`, `Models/*`, `Haptics`, `InterfaceOrientationLock`, `AppError`, `PHPhotoLibrary+Save`, `PromptBank`, `AppEntry`, `Date+Formatting`, `FileManager+Documents`, `CoachCopy`, `CoachStep` | backend | read-only |
| `*ViewModel.swift` | backend | frontend asks via contract request |
| `Shared/Constants.swift` | frontend: `CameraUI`, `Onboarding`, `DetailUI`, layout; backend: `Camera`, `ImageProcessing`, `Strip`, `Diary` | own namespace only |
| `frmrTests/*` | each implementer for its own logic; QA owns `*AcceptanceTests` / `*RegressionTests` | never delete another agent's test |
| `CLAUDE.md`, `project.md`, `frmr-v*-spec.md` | lead only | propose text in report |

**Contract request.** To get something outside your files, send the lead: `CONTRACT REQUEST — need <property/method/constant> on <type>, signature <...>, because <...>.` The lead relays it to the owner.

**QA reports, owners fix.**

`scripts/frmr-guard.sh` (`--all`, or `--hook` on every agent edit) enforces the hard constraints mechanically.
