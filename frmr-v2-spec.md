# frmr — v2 Feature Specification

**Date:** 2026-07-31  
**Baseline:** v1 build, all six phases complete, 11 tests passing, compiling without warnings.  
**Context files:** Read alongside `CLAUDE.md` (engineering rules) and `project.md` (full product spec). All constraints from those documents apply here.

---

## Overview

v2 is a polish and feel release. No new user flows, no new data models, no new screens. Every feature in this document makes the existing flows feel more physical, more deliberate, and more like a real film camera and darkroom. The ethos from §1 — *intentional, user-initiated, offline, no AI* — governs every decision.

Eight features, grouped into three themes:

| Theme | Features |
|---|---|
| **Camera feel** | F1 Tap-to-focus/expose · F2 Swipe exposure compensation · F3 Pinch-to-zoom |
| **Film grain** | F4 Luminosity-weighted grain · F5 Film stock profiles · F6 Animated preview grain |
| **Strip & flow** | F7 Sprocket holes + frame numbers · F8 Haptics + prompt typewriter |

---

## F1 — Tap-to-focus and tap-to-expose

### What it is

A tap anywhere on the live viewfinder sets both the focus point and the exposure metering point at that location. A brief focus-lock indicator (a square that draws in and fades out) confirms where the camera locked.

### Why

This is the single biggest quality-of-life improvement for photo output. Currently focus and exposure are always center-weighted. Tap-to-focus is standard for any serious camera app and is the most-noticed missing feature in a photography journal.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CaptureSession.swift` | Add `setFocusAndExposure(at point: CGPoint)` — converts a view-space point to `AVCaptureDevice.focusPointOfInterest` (normalised 0–1 space via `previewLayer.captureDevicePointConverted`) and applies `.autoFocus` + `.autoExpose`, then locks to `.locked` after subject lock via `addObserver` on `isAdjustingFocus` |
| `Features/Camera/CameraViewModel.swift` | Add `@Published var focusPoint: CGPoint?` and `func userTapped(at:)` that calls `CaptureSession.setFocusAndExposure` and sets `focusPoint` (cleared after `Constants.Camera.focusIndicatorDuration`) |
| `Features/Camera/CameraView.swift` | Add `.onTapGesture { location in viewModel.userTapped(at: location) }` on the viewfinder layer; overlay `FocusIndicatorView` at `focusPoint` when non-nil |
| `Shared/Components/FocusIndicatorView.swift` | **New file.** A 72×72pt square ring (1.5pt stroke, white) that animates: scale 1.2→1.0 over 0.15s on appear, opacity 1→0 over 0.4s after a 0.5s hold. Pure SwiftUI, no logic. |
| `Shared/Constants.swift` | Add `Camera.focusIndicatorSize`, `Camera.focusIndicatorStroke`, `Camera.focusIndicatorDuration`, `Camera.focusSettleDuration` |

### AVFoundation notes

- `setFocusPointOfInterest` requires `isFocusPointOfInterestSupported` — guard this. Front camera often does not support it; fail silently (no indicator, no error alert — the camera just stays center-focused as before).
- Point conversion: `previewLayer.captureDevicePointConverted(fromLayerPoint:)` returns the normalised `CGPoint` in device space. This call is safe to make on the main thread; the subsequent device configuration must happen inside `device.lockForConfiguration()`.
- After `.autoFocus` triggers, listen to `AVCaptureDevice.isAdjustingFocus` KVO. Once it settles (`false`), optionally switch to `.locked` to prevent the camera hunting. This is the `Constants.Camera.focusSettleDuration` timeout path: if KVO doesn't fire within the timeout, leave in continuous mode. Mark with `// OPEN: decide whether to lock focus after tap or stay in auto`.
- Session queue discipline: `setFocusAndExposure` must call `device.lockForConfiguration()` on the `CaptureSession`'s private queue, not the main thread.

### Tests

`CaptureSession` wraps hardware — not directly unit testable. Write a `FocusIndicatorViewTests` snapshot-style check (appear → settle state) if snapshot testing is available; otherwise document as "requires device".

---

## F2 — Swipe-up exposure compensation

### What it is

A vertical drag gesture on the viewfinder adjusts the camera's exposure bias (EV). A small sun icon and numeric EV value appear on the right edge of the viewfinder while the user is dragging; they fade out one second after the drag ends. Range: −2.0 EV to +2.0 EV.

### Why

Paired with tap-to-focus, this gives the user the same two controls they'd reach for on a real camera — where to focus, and how bright to expose. It reinforces the intentional, physical feel of the app. Native iOS camera uses this exact gesture.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CaptureSession.swift` | Add `func setExposureBias(_ ev: Float)` — clamps to `device.minExposureTargetBias...device.maxExposureTargetBias`, calls `setExposureTargetBias(_:completionHandler:)` inside `lockForConfiguration` block on session queue |
| `Features/Camera/CameraViewModel.swift` | Add `var exposureBias: Float = 0.0` and `var isDraggingExposure: Bool = false`; add `func adjustExposure(dragDelta: CGFloat)` that maps drag distance to EV delta and calls `CaptureSession.setExposureBias` |
| `Features/Camera/CameraView.swift` | Add `.gesture(DragGesture().onChanged { }.onEnded { })` on the viewfinder; overlay `ExposureIndicatorView` when `isDraggingExposure || exposureBias != 0` |
| `Shared/Components/ExposureIndicatorView.swift` | **New file.** SF Symbol `sun.max.fill` + formatted EV string (e.g. `+0.7`). Right-edge positioned. Fades in on drag start, fades out `Constants.Camera.exposureIndicatorFadeDelay` after drag ends. Pure SwiftUI. |
| `Shared/Constants.swift` | Add `Camera.exposureBiasRange` (`-2.0...2.0`), `Camera.exposureDragScale` (pts-of-drag per 1 EV step, default 80), `Camera.exposureIndicatorFadeDelay` (1.0s) |

### Gesture mapping

```
EV delta = -dragTranslation.height / Constants.Camera.exposureDragScale
```

Drag upward (negative `translation.height`) → positive EV (brighter). Clamped to `exposureBiasRange`. The negative sign is intentional — swipe up = more light = matches user intuition.

### Notes

- `setExposureTargetBias` is available on all devices supporting `AVCaptureDevice.isExposureModeSupported(.custom)`. Guard on `device.isExposureModeSupported(.continuousAutoExposure)` at minimum. On devices that don't support it, hide the gesture silently — no indicator, no error.
- After tap-to-expose (F1) locks the exposure point, EV bias still works — they are orthogonal controls. This is the correct behaviour and matches the native camera.
- EV bias persists for the session but resets to 0.0 on camera flip (call `setExposureBias(0.0)` in `switchCamera`).
- `// OPEN: decide whether EV bias should persist across launches` — default: no persistence, reset to 0.0 on each launch.

### Tests

Pure logic: test the drag-to-EV mapping function (input delta → expected clamped EV) in `frmrTests`.

---

## F3 — Pinch-to-zoom

### What it is

A pinch gesture on the viewfinder smoothly adjusts the camera zoom factor. This is a continuous analogue to the existing discrete 0.5×/1×/Tele chip buttons.

### Why

The lens chips are good for deliberate jumps, but feel coarse for composition. Pinch zoom is the muscle memory for every iPhone user and makes the camera feel complete. The two controls coexist: chips jump to named focal lengths; pinch gives fine control in between.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CaptureSession.swift` | Add `func setZoom(_ factor: CGFloat, animated: Bool)` — clamps to `device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor`, calls `device.ramp(toVideoZoomFactor:withRate:)` when animated, `device.videoZoomFactor` directly when not |
| `Features/Camera/CameraViewModel.swift` | Add `var zoomFactor: CGFloat = 1.0` and `var pinchBaseZoom: CGFloat = 1.0`; add `func pinchBegan()` (captures base) and `func pinchChanged(scale: CGFloat)` (applies delta) |
| `Features/Camera/CameraView.swift` | Add `.gesture(MagnificationGesture().onChanged { }.onEnded { })` on the viewfinder |
| `Shared/Constants.swift` | Add `Camera.zoomRampRate` (rate for animated zoom, default `4.0`), `Camera.maxZoomFactor` (soft cap, default `10.0` — devices can go higher but quality degrades) |

### Notes

- `videoZoomFactor` and lens switching (`switchCamera(to:lens:)`) operate on the same device property. When the user switches lens chip, set `zoomFactor = 1.0` for the new lens. When user pinches past a lens boundary (e.g. pinching past 2× on an ultrawide which physically jumps to the main lens), AVFoundation handles the optical switch automatically — don't model it separately.
- Front camera: `minAvailableVideoZoomFactor` is 1.0, max is usually 1.0 too (no zoom). Guard against a zero-range and disable the gesture silently.
- Double-tap to reset zoom to 1.0 is a small addition that pairs well. Add `TapGesture(count: 2)` with `.simultaneously` alongside the drag gesture from F2. One extra line in `CameraView`.

### Tests

Test the zoom clamping logic (input scale × base → expected clamped factor) in `frmrTests`.

---

## F4 — Luminosity-weighted grain

### What it is

Upgrade the existing flat `CINoiseReduction` grain pass so that grain intensity varies by luminance — heavier in shadows and highlights, lightest in midtones. This matches how actual photographic film responds to light.

### Why

The current grain (a flat noise overlay) reads as a Photoshop texture rather than film. Luminosity weighting is the single change that makes synthetic grain look photographic. It has no UI impact — same toggles, better result.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/ImageProcessor.swift` | Replace the flat grain pass with the multi-step pipeline below |
| `Shared/Constants.swift` | Add `ImageProcessing.grainShadowWeight`, `grainHighlightWeight`, `grainMidtoneWeight`, `grainBlendMode` |

### Pipeline (CoreImage, no deps)

```
Input image
  └─ CIColorControls(saturation: 0) → luminance mask
       └─ CIGaussianBlur(radius: 1) → soft mask (avoid noise at hard edges)
  └─ CIRandomGenerator → raw noise tile
       └─ CIColorMatrix → scale noise to grain intensity
       └─ CIBlendWithMask(background: zeroGrain, foreground: fullGrain, mask: luminanceMask) → shaped grain
  └─ CIBlendWithAlphaMask or CISourceOverCompositing → composite onto original
```

The luminance mask is a greyscale image where:
- Pure black (shadows) → value near 1.0 (maximum grain)  
- Mid grey (midtones) → value near 0.3 (minimum grain)
- Pure white (highlights) → value near 0.8 (heavy grain, less than shadows)

This U-curve response matches the real film response curve. Implement as a `CIColorCurves` filter on the luminance mask image, with the control points stored in `Constants.ImageProcessing.grainLuminanceCurve`.

### Notes

- `CIRandomGenerator` produces a static tile each call. For still-image processing (strip generation), static grain is correct. For animated preview grain (F6), this tile must be regenerated each frame.
- `CIColorCurves` is iOS 13+ — fine for the iOS 17 deployment target.
- Mark initial curve control point values with `// OPEN: grain curve tuning — values need calibration against real RAW captures`. Start with `[(0.0, 1.0), (0.5, 0.3), (1.0, 0.8)]`.
- The grain blend mode over the original image should be `CIBlendWithMask` compositing, not a simple overlay — overlay washes out colour. The grain layer is added as a luminance-only perturbation.

### Tests

`ImageProcessorTests`: given a solid-black input image, assert that the output pixel variance (grain) is greater than on a solid-mid-grey input. This is a regression test for the weighting, not a pixel-perfect test.

---

## F5 — Film stock profiles

### What it is

Three named film stock profiles that bundle grain intensity, grain scale, and a subtle colour cast into a single named constant group. Selected in Settings → Strip defaults (replaces the current binary grain on/off toggle with a picker: Off / ISO 100 / ISO 400 / ISO 3200).

### Why

The on/off grain toggle is good but coarse. Real film selection is a creative choice with distinct visual personalities. Three profiles give users creative range without adding complexity — it's one extra picker in Settings, zero new screens.

### Film stock profiles

| Name | Grain intensity | Grain scale | Colour cast | Character |
|---|---|---|---|---|
| **ISO 100** | 0.04 | 1.0 | Neutral (no cast) | Fine, almost invisible grain. Clean, documentary feel. |
| **ISO 400** | 0.12 | 1.5 | Warm (+3% red, +1% green) | Visible grain. Classic 35mm look. Default. |
| **ISO 3200** | 0.30 | 2.5 | Warm-green push (+4% red, +5% green, -2% blue) | Heavy grain. Pushed film, night photography feel. |

The colour cast is applied as a `CIColorMatrix` before the grain pass so the grain itself is neutral-coloured.

### Files changed

| File | Change |
|---|---|
| `Models/StripCustomization.swift` | Replace `filmGrain: Bool` with `filmStock: FilmStock` where `FilmStock` is `enum FilmStock: String, CaseIterable, Codable { case none, iso100, iso400, iso3200 }` |
| `Features/Camera/ImageProcessor.swift` | Read `FilmStock` from `StripCustomization`; apply the profile's cast + grain parameters |
| `Features/Strip/StripView.swift` | Replace grain toggle with a `Picker` of `FilmStock.allCases` |
| `Features/Settings/SettingsView.swift` | Replace grain toggle in Strip defaults with same `FilmStock` picker |
| `Shared/Constants.swift` | Add `ImageProcessing.FilmStockProfile` struct with fields `grainIntensity`, `grainScale`, `colourMatrix: [Float]`; add three static instances `iso100`, `iso400`, `iso3200` |
| `frmrTests/frmrTests.swift` | Update any existing grain toggle tests to use the new `FilmStock` enum |

### Notes

- `FilmStock.none` is the equivalent of the old `filmGrain: false` — no grain, no cast. Existing saved strips with `filmGrain: false` migrate to `.none`, `filmGrain: true` migrates to `.iso400` (closest to the old default). Add a migration note in `DailyStrip`.
- SwiftData schema migration: if `StripCustomization` is stored as a `Codable` blob inside `DailyStrip`, the migration is automatic via the `Codable` default. If it's modelled as SwiftData attributes directly, a lightweight migration is needed. Check the current `StripCustomization` implementation before coding.
- `// OPEN: colour cast values need calibration against real device captures. Starting values are aesthetic estimates.`

### Tests

`ImageProcessorTests`: for each `FilmStock` case, assert that the output image has the expected relative warmth (red channel mean > blue channel mean for iso400/iso3200, equal for iso100/none).

---

## F6 — Animated grain on live preview

### What it is

While the camera viewfinder is live, the grain texture regenerates every N frames, so the grain shifts between frames. Currently the grain is a static overlay, which reads as a filter rather than real film grain.

### Why

Film grain is in motion between frames. A static grain texture immediately reads as digital. Animating it costs some GPU cycles but makes the viewfinder feel like a real camera rather than a phone app with a filter.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CameraView.swift` | Add a `TimelineView(.animation(minimumInterval: Constants.Camera.grainRefreshInterval))` wrapper around the grain overlay layer |
| `Shared/Components/GrainOverlayView.swift` | **New file.** A SwiftUI `Canvas` that draws a fresh `CIRandomGenerator` noise tile each time it's called. Accepts a `Date` seed from `TimelineView` to force redraw. Blended at `Constants.Camera.liveGrainOpacity` using `.luminosity` blend mode. |
| `Shared/Constants.swift` | Add `Camera.grainRefreshInterval` (default `0.083` = ~12fps), `Camera.liveGrainOpacity` (default `0.08`) |

### Notes

- `TimelineView` drives redraws at the specified interval. The grain tile itself is generated inside `Canvas.draw` using `CIContext` + `CIRandomGenerator`. The context should be created once and stored, not recreated each frame.
- **Benchmark first.** On an A15 or earlier device, per-frame CoreImage noise generation may cause frame drops. Add an `// OPEN: benchmark animated grain on A15 — disable if frame rate drops below 24fps` comment and a toggle in `Constants.swift` (`Camera.animatedGrainEnabled = true`) so it can be quickly disabled.
- The animated grain is preview-only. Strip generation continues to use the static, higher-quality luminosity-weighted grain from F4.
- The grain overlay uses `.luminosity` blend mode so it doesn't desaturate colours. It only affects brightness values — this is the correct blend mode for film grain.
- Live grain intensity should be lower than strip grain intensity (`liveGrainOpacity` vs `grainIntensity`) since the viewfinder grain is additive on top of whatever the device is already showing.

### Tests

Cannot unit-test frame rendering. Document as "requires device; verify grain visibly shifts between frames at 12fps".

---

## F7 — Sprocket holes, frame numbers, and date stamp on strip

### What it is

Three visual upgrades to the rendered film strip in `StripGenerator`:

1. **Sprocket holes** — two columns of punched-out circles along the left and right edges of the strip, in the white border area. 4 holes per frame, evenly spaced vertically.
2. **Frame numbers** — small orange monospace numerals (`01`, `02`, `03`, `04`) printed in the border below each frame, right-aligned. Same font as the existing date stamp.
3. **Date stamp upgrade** — the existing date stamp at the bottom of the strip moves into the right-side sprocket column, rotated 90°, printed orange. Matches the look of DX-coded film borders.

### Why

These details are the difference between "a strip with a film look" and "a strip that looks like it actually came out of a photobooth". Sprocket holes in particular are the element users will recognise immediately as authentic. They cost no UX — they're pure `CoreGraphics` in `StripGenerator`.

### Files changed

| File | Change |
|---|---|
| `Features/Strip/StripGenerator.swift` | Add three new drawing passes after compositing the 4 photo slots: `drawSprocketHoles(_:in:context:)`, `drawFrameNumbers(_:in:context:)`, `drawRotatedDateStamp(_:date:in:context:)` |
| `Shared/Constants.swift` | Add `Strip.sprocketHoleRadius`, `Strip.sprocketHoleCount` (per frame, default 2 per side), `Strip.sprocketHoleColor` (white with 80% opacity for punched look), `Strip.frameNumberFontSize`, `Strip.frameNumberColor` (amber `#EE9B00`), `Strip.datestampRotation` (90° for vertical text) |

### Sprocket hole geometry

The strip has a 6pt white border on all sides (existing spec, §10). Sprocket holes are drawn within this border area:

```
Hole centre X (left column):  3pt from left edge
Hole centre X (right column): strip width − 3pt from right edge
Hole radius:                  Constants.Strip.sprocketHoleRadius (default 3.5pt)
Holes per frame side:         2 (top half and bottom half of each frame slot)
Hole fill:                    near-black (#001219) — punched through to "dark backing"
```

Draw holes using `CGContext.addEllipse(in:)` + `CGContext.setFillColor` + `.fillPath`. The holes are drawn after all photo compositing so they appear on top of everything, including any overflowing photo pixels.

### Frame number geometry

```
Position: below each photo slot, inside the bottom border strip
Font:      SF Mono, Constants.Strip.frameNumberFontSize (default 6pt at 2× = 12px)
Color:     Constants.Strip.frameNumberColor (amber)
Format:    "%02d" — "01", "02", "03", "04"
Alignment: right-aligned within each slot's column
```

### Date stamp (rotated)

The existing bottom date stamp remains for readability. Add a secondary rotated copy in the right border:

```
Rotation:  -90° (reads bottom-to-top along the right edge)
Position:  right border, vertically centred on the full strip height
Font:      existing monospace date stamp font, same size
Color:     amber
```

Use `CGContext.saveGState()` / `.translateBy` / `.rotate` / `.restoreGState()` for the rotation pass. This is pure CoreGraphics — no new APIs.

### Tests

`StripGeneratorTests`: assert that the rendered strip image at the expected size contains non-white pixels in the sprocket hole positions (sample specific pixel coordinates). Assert frame number pixels exist in the expected position. These are regression tests for layout correctness.

---

## F8 — Haptics and prompt typewriter effect

Two small, independent changes bundled together because they share no code and each takes < 1 hour.

---

### F8a — Haptic feedback

Three haptic moments, each a one-liner:

| Moment | Generator | Style | Where |
|---|---|---|---|
| Shutter tap | `UIImpactFeedbackGenerator` | `.heavy` | `CameraViewModel.capturePhoto()` — fire just before triggering capture |
| Focus lock | `UIImpactFeedbackGenerator` | `.light` | `CaptureSession` focus KVO observer — fire when `isAdjustingFocus` transitions `true → false` |
| Strip complete | `UINotificationFeedbackGenerator` | `.success` | `StripViewModel` — fire when strip render completes |

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CameraViewModel.swift` | Add `UIImpactFeedbackGenerator(style: .heavy).impactOccurred()` in `capturePhoto()` |
| `Features/Camera/CaptureSession.swift` | Add `UIImpactFeedbackGenerator(style: .light).impactOccurred()` in the focus-lock KVO handler (added in F1) |
| `Features/Strip/StripViewModel.swift` | Add `UINotificationFeedbackGenerator().notificationOccurred(.success)` after successful strip render |

### Notes

- `UIImpactFeedbackGenerator` should be instantiated and `prepare()`d slightly before use for lower latency. Add `prepare()` calls in the appropriate "about to capture" / "about to render" paths.
- Haptics are `UIKit` APIs. In SwiftUI, call them from the ViewModel (which is already on the main actor) — not from the View body.
- No `// OPEN:` needed — haptics are always-on. If a user has haptics disabled at the system level, `UIFeedbackGenerator` silently no-ops.

### Tests

Haptic timing is not unit-testable. Document as "verify on device".

---

### F8b — Prompt typewriter effect

The prompt text in `EntryEditorView` reveals character-by-character on appear, at a fixed interval, giving the impression of the prompt being typed out for the user.

### Files changed

| File | Change |
|---|---|
| `Features/Diary/EntryEditorView.swift` | Replace static prompt `Text` with `TypewriterText` component |
| `Shared/Components/TypewriterText.swift` | **New file.** A SwiftUI view that takes `fullText: String` and `interval: TimeInterval`, reveals one character per interval tick using a `Task` + `try await Task.sleep`. Exposes the revealed string as `@State var displayed: String = ""`. Uses `async/await` — no `Timer`, no Combine. |
| `Shared/Constants.swift` | Add `Diary.promptTypewriterInterval` (default `0.03` seconds per character — fast enough to not feel slow, slow enough to register as deliberate) |

### Implementation pattern

```swift
// TypewriterText.swift
struct TypewriterText: View {
    let fullText: String
    @State private var displayed = ""
    
    var body: some View {
        Text(displayed)
            .task {
                for char in fullText {
                    displayed.append(char)
                    try? await Task.sleep(
                        nanoseconds: UInt64(Constants.Diary.promptTypewriterInterval * 1_000_000_000)
                    )
                }
            }
    }
}
```

The `Task` is automatically cancelled when the view disappears, so navigating away (Retake) stops the animation cleanly.

### Notes

- The typewriter runs on task start. If the user taps the text field before the animation completes, the full prompt should immediately snap to complete. Add a `onTapGesture { displayed = fullText }` shortcut.
- `try?` on `Task.sleep` is correct here — a `CancellationError` on view disappear should be silently swallowed.
- No `// OPEN:` needed. If the interval needs tuning after device testing, change `Constants.Diary.promptTypewriterInterval`.

### Tests

`TypewriterTextTests`: given a 5-character string and a 0.01s interval, assert that after 0.06s the displayed text equals the full string. Use Swift's `async` test support (`@MainActor func testTypewriter() async throws`).

---

## Constants additions (summary)

All new values to add to `Constants.swift`, grouped by namespace:

```swift
// Camera
Camera.focusIndicatorSize         = 72.0
Camera.focusIndicatorStroke       = 1.5
Camera.focusIndicatorDuration     = 1.2    // total animation duration
Camera.focusSettleDuration        = 2.0    // OPEN: lock after settle or stay continuous?
Camera.exposureBiasMin            = -2.0
Camera.exposureBiasMax            = 2.0
Camera.exposureDragScale          = 80.0   // pts drag per 1 EV
Camera.exposureIndicatorFadeDelay = 1.0
Camera.zoomRampRate               = 4.0
Camera.maxZoomFactor              = 10.0
Camera.grainRefreshInterval       = 0.083  // ~12fps, OPEN: benchmark on A15
Camera.liveGrainOpacity           = 0.08
Camera.animatedGrainEnabled       = true   // OPEN: disable if frame drops

// ImageProcessing
ImageProcessing.grainLuminanceCurve     = [(0.0, 1.0), (0.5, 0.3), (1.0, 0.8)]  // OPEN: calibrate
ImageProcessing.FilmStockProfile.iso100 = { intensity: 0.04, scale: 1.0, cast: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1] }
ImageProcessing.FilmStockProfile.iso400 = { intensity: 0.12, scale: 1.5, cast: [1.03,0,0,0, 0,1.01,0,0, 0,0,1,0, 0,0,0,1] }  // OPEN: calibrate cast
ImageProcessing.FilmStockProfile.iso3200 = { intensity: 0.30, scale: 2.5, cast: [1.04,0,0,0, 0,1.05,0,0, 0,0,0.98,0, 0,0,0,1] }  // OPEN: calibrate cast

// Strip
Strip.sprocketHoleRadius  = 3.5
Strip.sprocketHoleCount   = 2       // per frame per side
Strip.frameNumberFontSize = 6.0     // points (2× = 12px in renderer)
Strip.frameNumberColor    = #EE9B00 // amber
Strip.datestampRotation   = -90.0   // degrees

// Diary
Diary.promptTypewriterInterval = 0.03   // seconds per character
```

---

## New files summary

| File | Feature | Type |
|---|---|---|
| `Shared/Components/FocusIndicatorView.swift` | F1 | SwiftUI view |
| `Shared/Components/ExposureIndicatorView.swift` | F2 | SwiftUI view |
| `Shared/Components/GrainOverlayView.swift` | F6 | SwiftUI view + Canvas |
| `Shared/Components/TypewriterText.swift` | F8b | SwiftUI view |

No new model files. No new feature directories. No new screens.

---

## Open decisions introduced by v2

These join the existing `// OPEN:` list from project.md §13:

| # | Decision | Default |
|---|---|---|
| v2-1 | Lock focus after tap-to-focus settles, or stay in continuous auto? | Stay continuous (less jarring if subject moves) |
| v2-2 | Persist EV bias across launches? | No — reset to 0.0 on each launch |
| v2-3 | Animated grain: disable threshold frame rate? | Disable if <24fps sustained — benchmark on A15 |
| v2-4 | Grain luminance curve control points | `[(0.0, 1.0), (0.5, 0.3), (1.0, 0.8)]` pending calibration on real RAW |
| v2-5 | Film stock colour cast matrix values | Starting estimates — need calibration on device |

---

## Sequencing recommendation

Build in this order to minimise integration risk:

1. **F8a (haptics)** — three one-liners, zero risk, immediate feel improvement. Build first to get a win.
2. **F8b (typewriter)** — self-contained new component, no existing code touched.
3. **F7 (sprocket holes + frame numbers)** — pure `CoreGraphics` in an already-tested module. Easy to verify by looking at strip output.
4. **F1 (tap-to-focus)** — requires device for full verification. Build the ViewModel/Session logic first, test focus indicator in simulator.
5. **F2 (exposure compensation)** — builds on F1's session queue discipline. Do after F1.
6. **F3 (pinch-to-zoom)** — builds on F1/F2's gesture layer. Do after F2.
7. **F4 (luminosity grain)** — CoreImage pipeline change. Has unit-testable output. Can be done in parallel with F1–F3.
8. **F5 (film stock profiles)** — depends on F4 being in place. Do after F4.
9. **F6 (animated preview grain)** — last because it depends on F4 and requires device benchmarking.

---

## Definition of done (v2)

A v2 feature is shippable when:
- [x] All v1 definition-of-done criteria still pass (no regressions)
- [x] All 8 features work end-to-end on a physical device (camera features) or in simulator (strip/flow features) — *simulator-verifiable parts done; F1/F2/F3 and the haptics still need a device pass, see §Implementation status*
- [x] All new `// OPEN:` items are marked in code and have values in `Constants.swift`
- [x] No force-unwraps in new production paths
- [x] All new errors surface to the user via the existing `AppError`/`AppErrorAlert` system
- [x] New unit-testable logic has tests (`ImageProcessorTests` grain weighting, `StripGeneratorTests` sprocket geometry, `TypewriterTextTests`, EV drag mapping, zoom clamping)
- [x] `Constants.swift` contains all new magic values — nothing buried inline
- [x] Code compiles without warnings

---

## Implementation status — v2 build (2026-07-31)

All eight features are implemented. The project builds clean with zero warnings and **28 unit tests pass** (11 pre-existing + 17 new).

### Per-feature outcome

| # | Feature | Status | Notes / deviations from spec |
|---|---|---|---|
| F1 | Tap-to-focus / expose | ✅ Built | Focus **and** exposure point set together; both guarded on device support and fail silently. Focus-settle KVO fires the light haptic. **Needs device verification.** |
| F2 | Swipe exposure compensation | ✅ Built | Drag→EV mapping is a pure static function and unit-tested. **Needs device verification.** |
| F3 | Pinch-to-zoom | ✅ Built | Clamping is pure and unit-tested. Double-tap resets zoom. Silently inert when the camera reports a zero-width zoom range. **Needs device verification.** |
| F4 | Luminosity-weighted grain | ✅ Built + verified | Visually confirmed in a rendered strip. **One spec gap fixed — see below.** |
| F5 | Film stock profiles | ✅ Built + verified | Picker live in both Strip and Settings; legacy `filmGrain: Bool` migrates on read. |
| F6 | Animated preview grain | ✅ Built + verified | Grain visibly textures the viewfinder in the simulator. **A15 frame-rate benchmark still outstanding** (v2-3). |
| F7 | Sprocket holes / frame numbers / date stamp | ✅ Built + verified | Rendered strip inspected directly. **Two layout deviations — see below.** |
| F8a | Haptics | ✅ Built | Centralised in `Shared/Haptics.swift`. **Needs device verification.** |
| F8b | Prompt typewriter | ✅ Built + verified | Reveal loop extracted so it's testable without a view host. |

### Deviations from the written spec (and why)

**F4 — grain was invisible until the pipeline learned about output size.**
The spec's pipeline is correct but incomplete. Grain is a *per-pixel* effect: generating it at a capture's native resolution and then compositing that photo into a 260px strip slot averages the noise away entirely. A rendered ISO 3200 strip came out perfectly smooth. `ImageProcessor.applyStripLook` now takes an optional `outputWidth:`, and `StripGenerator` passes the destination width so the noise tile is pre-scaled to compensate. Without this, F4 and F5 are both no-ops on real captures.

**F7 — frame numbers get a reserved gutter.**
The spec places them "right-aligned within each slot's column", which collides with a long left-aligned caption in the same band. The caption rect is now narrowed by `Layout.frameNumberColumnWidth`, giving the number a dedicated column that a caption can never run into.

**F7 — the rotated date stamp is smaller than the bottom stamp.**
At 8pt it does not fit inside the 6pt paper border. It's drawn at `Strip.edgeDateFontSize` (5pt) instead, and the sprocket holes are drawn *over* it — which is what real DX edge printing looks like, since perforations interrupt the printed text. Worth a look: as specced it appears exactly once, vertically centred, which reads slightly like a stray mark. Repeating it down the edge would be more authentic but is a deliberate change to the spec, so it was left alone.

**F1 — exposure point is set alongside the focus point.**
The spec titles this "tap-to-focus and tap-to-expose" but the file table only describes focus. Both are set in one `lockForConfiguration` block, each independently guarded.

**F2 — indicator visibility rule.**
The spec gives two rules that conflict (fade out 1s after drag ends; show whenever `exposureBias != 0`). Resolved as: visible while dragging, visible while the bias is non-zero, plus a 1s linger after release so a return-to-zero drag doesn't vanish instantly.

### Files added

| File | Feature |
|---|---|
| `Shared/Components/FocusIndicatorView.swift` | F1 |
| `Shared/Components/ExposureIndicatorView.swift` | F2 |
| `Shared/Components/GrainOverlayView.swift` | F6 |
| `Shared/Components/TypewriterText.swift` | F8b |
| `Shared/Haptics.swift` | F8a — not in the spec's file list; the three call sites all need pre-warmed generators, so they share one holder rather than instantiating inline |

### Files changed

`Shared/Constants.swift` (new `Camera`, `Diary` namespaces; `ImageProcessing.FilmStockProfile` + grain curve; `Strip` edge detailing) · `Models/StripCustomization.swift` (`FilmStock` enum replacing `filmGrain`) · `Features/Camera/CaptureSession.swift` (focus/exposure/zoom, focus KVO) · `CameraViewModel.swift` (gesture state + pure mappings) · `CameraView.swift` (gesture layer, indicators, grain overlay, preview-layer handback) · `ImageProcessor.swift` (luminosity grain, colour cast, live grain tile) · `Features/Strip/StripGenerator.swift` (three edge-detail passes) · `StripViewModel.swift` (stock default + migration, strip haptic) · `StripView.swift` + `Features/Settings/SettingsView.swift` (stock picker) · `Shared/Components/PromptCard.swift` (typewriter) · `frmrTests/frmrTests.swift`

### Tests added (17)

- `ImageProcessorTests` — shadow grain > midtone grain (the F4 U-curve); ISO 3200 > ISO 100; `.none` returns the input untouched; warm stocks push red above blue while ISO 100 stays neutral; live grain tile differs between frames
- `StripGeneratorTests` — sprocket holes punched in both borders; paper stays white between holes; amber frame number present in its gutter
- `CameraControlMappingTests` — drag up brightens / down darkens; EV clamping; EV accumulates from the drag-start bias; zoom clamping; zoom inert on a zero-width range
- `FilmStockMigrationTests` — legacy Bool → stock mapping; every stock except `.none` has a profile
- `TypewriterTextTests` — characters revealed in order; empty string produces no frames

Test helpers: a `PixelBuffer` RGBA reader so the rendering tests assert on actual output rather than on the code that produced it.

### Verified how

- **Strip output (F4, F5, F7):** rendered to PNG and inspected directly — sprocket holes on both edges, amber `01`–`04` in the gutter, captions truncating before the gutter, rotated edge stamp, and visible ISO 3200 grain that is correctly heavier in highlights than midtones.
- **Camera + Settings screens (F5, F6):** driven in the iPhone 17 Pro simulator; the animated grain visibly textures the viewfinder, and the Film stock picker has replaced the grain toggle in Strip defaults.
- **Not yet verified:** F1, F2, F3 and all three haptics require a physical device. The simulator has no camera, so `CaptureSession`'s focus/exposure/zoom paths never execute there.

### Still open after v2

| # | Decision | Current default in code |
|---|---|---|
| v2-1 | Lock focus after tap settles? | `Constants.Camera.lockFocusAfterTap = false` — stays continuous |
| v2-2 | Persist EV bias across launches? | `Constants.Camera.persistExposureBias = false` — resets on launch and on camera flip |
| v2-3 | Animated grain frame-rate threshold | `Constants.Camera.animatedGrainEnabled = true`; **A15 benchmark not yet run** |
| v2-4 | Grain luminance curve control points | `[1.0, 0.3, 0.8]` — not calibrated against real RAW |
| v2-5 | Film stock colour cast matrices | Aesthetic estimates — not calibrated on device |

All v1 open items from project.md §14 remain open and untouched.

---

## Post-v2 bugfix — camera view no longer rotates with the device (2026-08-24)

**Problem:** the interface autorotated with the device (Info.plist declares portrait + both landscapes on iPhone), so rotating the phone rotated the live `AVCaptureVideoPreviewLayer` along with everything else. That shifts the crop and framing the user is composing under them — not how a real camera behaves, and not "seamless."

**Fix:** the camera screen now locks the interface to portrait while it's on screen, so the preview never rotates; the chrome (mode toggle, lens/WB chips, shutter, flip button, permission overlay, focus and exposure indicators) counter-rotates in place to match how the phone is actually held, exactly like the stock Camera app's icon rotation.

| File | Change |
|---|---|
| `Shared/InterfaceOrientationLock.swift` | **New file.** Holds the app's current `UIInterfaceOrientationMask` and an `AppDelegate` implementing `application(_:supportedInterfaceOrientationsFor:)` that returns it. `lockToPortrait()` / `unlock()` update the mask and call `requestGeometryUpdate` so the change takes effect immediately rather than on the next rotation attempt. |
| `App/AppEntry.swift` | Added `@UIApplicationDelegateAdaptor(AppDelegate.self)` so the delegate above is wired in. |
| `Features/Camera/CameraViewModel.swift` | Added `uiRotationAngle: Angle`, driven by a `UIDevice.orientationDidChangeNotification` observer started in `startCamera()` / stopped in `stopCamera()`. The mapping itself is the pure static `rotationAngle(for:current:)` — face-up/face-down/unknown hold the last known angle instead of snapping to 0. |
| `Features/Camera/CameraView.swift` | `.task` locks to portrait (alongside starting the camera), `.onDisappear` unlocks (alongside stopping it) — same lifecycle the camera session already used. `.rotatingWithDevice(viewModel.uiRotationAngle)` is applied to each control **individually** — `ModeToggle`, `PhotoboothView`, `LensChipRow`, `WhiteBalanceControl`, `ShutterButton`, `FlipCameraButton`, `PermissionDeniedOverlay`, `FocusIndicatorView`, `ExposureIndicatorView` — never to the containing `VStack`, and never to `viewfinder`. |
| `Shared/Extensions/View+DeviceRotation.swift` | **New file.** `rotatingWithDevice(_:)` — `.rotationEffect` plus an `.easeInOut` animation keyed on the angle. |
| `Shared/Constants.swift` | Added `Camera.orientationRotationDuration = 0.3`. |
| `frmrTests/frmrTests.swift` | Two new tests on `CameraControlMappingTests` covering the four cardinal orientations and the face-up/face-down/unknown hold-last-angle behaviour. |

**Notes:**
- The first pass rotated the entire bottom-controls `VStack` as one unit, which broke: `.rotationEffect` doesn't reflow layout, it just spins the already-computed content around the container's own center within its existing (tall, narrow, portrait) bounding box. Content pinned to the top/bottom swung sideways and got clipped by that box instead of staying put — the mode toggle and lens chips in particular would appear to jump toward the center and get cut off on rotation. Fixed by rotating each control **individually, in place** (see the file table above) so every element's layout position is exactly what it already was in portrait; only its own icon/glyph spins, same as the stock Camera app.
- Only the Camera tab locks orientation — Library and Settings still rotate freely, since the lock is scoped to `CameraView`'s appear/disappear.
- The landscape-left/right → ±90° sign convention is the standard one used across camera-UI implementations, but it's only exercisable on a physical device (the simulator has no orientation sensor), so treat it as **unverified on device** alongside the rest of the v2 F1/F2/F3 gesture work.
- No new `// OPEN:` — this is a technical-correctness fix (the *whether* was decided by "camera view should not rotate"), not a deferred product decision. If the rotation direction turns out backwards on a real device, it's a four-line fix in `CameraViewModel.rotationAngle(for:current:)`.

### Tests

`CameraControlMappingTests.chromeCounterRotatesToTheFourCardinalOrientations` and `.chromeRotationHoldsLastKnownAngleOnFaceUpOrDown` — both pure, both passing. Build is clean (`xcodebuild build` and `xcodebuild test`, iPhone 17 Pro simulator, zero warnings).

---

## Post-v2 bugfix, part 2 — rotated chip rows overlapped neighbouring controls (2026-08-24)

**Problem:** per-element rotation (above) fixed clipping, but the white-balance and lens rows were still not usable once rotated. `WhiteBalanceControl` and `LensChipRow` lay their chips out side by side — wide and short. `.rotationEffect` paints a view's content rotated but the parent `VStack` still reserves layout space based on the view's **un-rotated** size. So a row that's wide-and-short pre-rotation paints tall-and-narrow post-rotation, without the extra height ever being reserved — it visually overlapped the mode toggle above it and the shutter row below it, which read as "not viewable."

**Fix:** both chip groups now stack their `CameraChip` pills vertically (one over another) instead of side by side. A column is narrow-and-tall *before* rotation, so once rotated it only ever gets **shorter** (and wider) — never taller than the space the `VStack` already reserved for it. `WhiteBalanceControl`'s `ScrollView` switched from `.horizontal` to `.vertical` with a capped height (`Constants.CameraUI.chipStackMaxHeight`) so its six modes scroll instead of pushing the shutter button down; `LensChipRow` (2–3 items) just stacks directly, no scroll needed.

| File | Change |
|---|---|
| `Features/Camera/WhiteBalanceControl.swift` | `ScrollView(.horizontal) { HStack {...} }` → `ScrollView(.vertical) { VStack {...} }`, capped at `Constants.CameraUI.chipStackMaxHeight`. |
| `Features/Camera/CameraView.swift` | `LensChipRow`'s `HStack` → `VStack`. |
| `Shared/Constants.swift` | Added `CameraUI.chipStackMaxHeight = 160`. |

**Notes:**
- Still unverified on a physical device, same as the rest of the v2 F1/F2/F3 gesture work and part 1 of this bugfix — the simulator has no orientation sensor to drive a real rotation through.

---

## Post-v2 bugfix, part 3 — two distinct layouts, not one that's always stacked (2026-08-24)

**Problem:** part 2 made the WB and lens chips permanently stacked, in both orientations. That's wrong — stacking only exists to survive the counter-rotation in landscape; in portrait there's no rotation happening at all, so the original side-by-side row is both correct and the more compact choice. There should be two distinct chrome layouts, not one layout used everywhere.

**Fix:** `CameraViewModel` now tracks a `ChromeLayout` (`.sideBySide` / `.stacked`) alongside `uiRotationAngle`, updated from the same device-orientation observer via a new pure `chromeLayout(for:current:)` mapping (portrait/portraitUpsideDown → side by side, landscapeLeft/Right → stacked, face-up/down/unknown → hold the last value, mirroring `rotationAngle`'s pattern). `WhiteBalanceControl`, `LensChipRow`, and now `ModeToggle` (Diary / Film strip) all take an `isStacked` flag and switch between an `HStack` and a `VStack` internally — chosen because a `ScrollView`'s scroll axis, and a segmented pill's Capsule shape, both need to change with the arrangement, not just get repainted at an angle.

| File | Change |
|---|---|
| `Features/Camera/CameraViewModel.swift` | Added `ChromeLayout` enum, `chromeLayout` property, `chromeLayout(for:current:)` pure mapping; `applyOrientation(_:)` now updates both `uiRotationAngle` and `chromeLayout` from the same notification callback. |
| `Features/Camera/WhiteBalanceControl.swift` | Takes `isStacked: Bool`; branches between the vertical/capped-height and horizontal/scrolling layouts from part 2. |
| `Features/Camera/CameraView.swift` | `LensChipRow` and `ModeToggle` both take `isStacked: Bool` and branch `HStack`/`VStack` the same way; all three call sites pass `viewModel.chromeLayout == .stacked`. |
| `frmrTests/frmrTests.swift` | `chipGroupsStackOnlyInLandscape` and `chipGroupLayoutHoldsLastKnownStateOnFaceUpOrDown` on `CameraControlMappingTests`. |

**Result:** portrait shows exactly the original v2 camera screen (side-by-side WB/lens chips, pill-shaped Diary/Film-strip toggle). Landscape hold shows every chip group — WB, lens, and the mode toggle — stacked one under another, matching how other camera apps handle a portrait-locked interface, and still counter-rotated in place so it reads upright.

### Tests

`chipGroupsStackOnlyInLandscape` and `chipGroupLayoutHoldsLastKnownStateOnFaceUpOrDown`, both pure, both passing. Build clean, zero warnings.

---

## Post-v2 bugfix, part 4 — flip-camera icon slid across the screen on rotation (2026-08-24)

**Problem:** `FlipCameraButton`'s own body was `HStack { Spacer(); Button(...) }` — a full-width, thin view that pushes its icon to the trailing edge internally. That's the same shape as the WB/lens rows fixed in part 2: wide and short. Rotating it 90° in place (as part 1 did for every control) swings that far-trailing icon position up or down around the view's center instead of leaving the icon where it visually sits — it read as the icon travelling across the screen rather than spinning in place.

**Fix:** `FlipCameraButton` is now just the icon button — no internal `HStack`/`Spacer`, so it has no long trailing edge to swing. The trailing screen position is produced by the call site instead, using `.overlay(alignment: .trailing)` on the (non-rotating) shutter `ZStack`, the same pattern already used for the focus and exposure indicators over the viewfinder. Only the small icon view itself gets `.rotatingWithDevice(...)`.

| File | Change |
|---|---|
| `Features/Camera/CameraView.swift` | `FlipCameraButton` body reduced to the bare `Button`. The shutter `ZStack` gained `.frame(maxWidth: .infinity)` and an `.overlay(alignment: .trailing) { FlipCameraButton(...) }` carrying the trailing padding and the rotation that used to live inside the button's own `HStack`. |

**Result:** the flip-camera icon now stays anchored to its fixed position near the shutter button and only its glyph rotates in place, matching the shutter button and every other icon-sized control.

No new tests — this is a pure layout fix with no new branching logic to unit test (unlike the `rotationAngle`/`chromeLayout` mappings). Build clean, zero warnings.

---

## Post-v2 bugfix, part 5 — bottom controls reached too far into the rotated screen (2026-08-24)

**Problem:** in landscape, the lens/WB/shutter cluster hugs one screen edge (see part 3) — but *how far it reaches in* from that edge is exactly however much vertical room it takes up back in the portrait buffer, since that's the dimension rotation swings from "near the bottom" to "reaching in from the edge." The gaps between `LensChipRow`, `WhiteBalanceControl`, and the shutter `ZStack` were an uncontrolled mix of explicit padding (`chipSpacing`, a default `.padding(.top)`) and the outer `VStack`'s implicit default spacing stacked on top of each other — noticeably more depth than needed, which read as the controls intruding toward the middle of the screen.

**Fix:** the three moved into their own inner `VStack(spacing: Constants.CameraUI.chipSpacing)`, replacing the mix of ad hoc paddings with one deliberate, tight gap between each. The default `.padding(.top)` on the shutter `ZStack` is gone entirely — `chipSpacing` from the `VStack` is the only gap now.

| File | Change |
|---|---|
| `Features/Camera/CameraView.swift` | `LensChipRow`, `WhiteBalanceControl`, and the shutter `ZStack` are now children of a `VStack(spacing: Constants.CameraUI.chipSpacing)` nested inside the screen's outer `VStack`, in place of per-child `.padding(.top, ...)` calls. |

**Result:** less blank space between the lens row, the WB row, and the shutter button in portrait, and — the actual point — a visibly shallower cluster reaching in from the edge once landscape rotates it, instead of pushing toward the middle of the screen.

No new tests — pure spacing change. Build clean, zero warnings.

---

## Post-v2 bugfix, part 6 — chips within a stacked group sat too far apart (2026-08-24)

**Problem:** on-device screenshot feedback (landscape hold) showed the lens chips (Tele/1×/0.5×) and WB chips (Shade/Cloudy/Daylight/Auto) each still using `Constants.CameraUI.chipSpacing` (8pt) between chips within their own stacked column — the same value used for the portrait side-by-side row. Once rotated, that read as loose, spaced-out gaps rather than one compact cluster.

**Fix:** added a smaller `Constants.CameraUI.stackedChipSpacing` (4pt), used only in the `isStacked` branch of `WhiteBalanceControl` and `LensChipRow`. The portrait `HStack` branches, and every other use of `chipSpacing` (the part 5 cluster gap, `StripView`'s chip rows), are untouched.

| File | Change |
|---|---|
| `Shared/Constants.swift` | Added `CameraUI.stackedChipSpacing = 4`. |
| `Features/Camera/WhiteBalanceControl.swift` | Stacked `VStack` now uses `stackedChipSpacing` instead of `chipSpacing`. |
| `Features/Camera/CameraView.swift` | `LensChipRow`'s stacked `VStack` — same change. |

No new tests — pure spacing change. Build clean, zero warnings.

---

## Post-v2 bugfix, part 7 — reverted (2026-08-24)

A part 7 briefly removed `.rotatingWithDevice(...)` from `LensChipRow` and `WhiteBalanceControl`, in response to an on-device screenshot where their chips appeared unrotated (side by side, upright text) while the mode toggle in the same screenshot correctly showed the rotated/stacked layout — an unexplained discrepancy given both read the same `viewModel.chromeLayout`/`uiRotationAngle`. That change was reverted at the user's request before the discrepancy was root-caused. Both controls are back to part 6's state: `isStacked` switches `HStack` → `VStack`, and `.rotatingWithDevice(viewModel.uiRotationAngle)` is applied on top, same as every other chrome control. If the on-device symptom recurs, it still needs a real device (not the simulator) to diagnose — the likely next step is confirming with a fresh build whether `chromeLayout` and `uiRotationAngle` actually reach these two views' bodies in that state, e.g. by temporarily rendering the raw values as text.
