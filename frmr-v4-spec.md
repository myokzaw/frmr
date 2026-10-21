# frmr — v4 Feature Specification

**Date:** 2026-10-20
**Baseline:** v3 build plus the post-v3 rotate-in-place rework. Compiles without warnings.
**Context files:** Read alongside `CLAUDE.md` (engineering rules) and `project.md` (full product spec). All constraints from those documents apply. `frmr-v2-spec.md` §F4–F6 (grain, film stocks, preview grain) is required background for every feature here. Read `.claude/skills/ios-camera-orientation/SKILL.md` before touching F0 or anything that creates a `CIImage` from a `UIImage`.

---

## Overview

v4 turns the strip look from "a colour cast plus noise" into a small, physically motivated film pipeline. It also fixes the bug that rotated photos as soon as any strip filter was switched on.

| Theme | Features | What it delivers |
|---|---|---|
| **A — Correctness and foundation** | F0 Orientation fix · F1 Downscale-first, float pipeline | Photos stay upright. The pipeline is fast enough to carry the heavier look. |
| **B — Film model** | F2 Characteristic curves · F3 Print stage | Tone and colour come from a negative curve followed by a print curve, not a single grade. |
| **C — Physical effects** | F4 Halation · F5 Grain v2 · F6 Bloom and light leak | The optical and chemical artefacts that make it read as film. |
| **D — Controls** | F7 Strip and Settings UI, model migration | The user can pick a stock, a print and effects. |

**Scope cuts.** Video is out of scope. The RAW development look (`ImageProcessor.process(rawData:)`) is unchanged. v4 changes only the strip-time look (`applyStripLook`).

**Ethos check.** Everything runs on device with Core Image built-in filters plus one Swift-generated colour cube. No network, no AI, no third-party code. Effects apply only when the user picks them. Nothing is randomised between renders of the same strip.

**Originality rule.** The look is built from published film science (characteristic curves, the negative and print chain, halation optics, the Boolean grain model). Do not copy another app's stock data, LUTs or presets. Do not use film brand or product names. Stocks get frmr's own names.

---

# Theme A — Correctness and foundation

## F0 — Strip filters rotated tagged photos ✅ fixed 2026-10-20

### Symptom

With the film stock Off and B&W off, the strip showed photos upright. Turning on grain or B&W rotated landscape-held photos 90°. Changing the background colour alone does not cause it; the reported screenshot also had ISO 100 on.

### Root cause

The post-v3 fix made every capture "unrotated sensor pixels plus an orientation tag". `applyStripLook` built its input with `CIImage(image:)`, which **ignores** `UIImage.imageOrientation`. It then rendered the result as `.up`, so the tag was dropped and the photo lay on its side. The early return when no filter is active passed the original tagged `UIImage` through, so "Off" looked correct and hid the bug. The v3 spec and `render(_:orientation:)`'s doc comment wrongly claimed that `CIImage(image:)` resolves orientation.

### Fix

`ImageProcessor.uprightCIImage(from:)` builds `CIImage(cgImage:)` and applies `.oriented(_:)` with the tag. The tag is mapped through a new explicit `cgOrientation(from:)` switch, never through `rawValue`. The wrong doc comment is corrected.

**Rule going forward:** never call `CIImage(image:)` on a photo in this app. Use `uprightCIImage(from:)`.

### Tests

- `ImageProcessorTests.cgOrientationRoundTripsEveryCase`
- `ImageProcessorTests.stripLookKeepsATaggedPhotoUpright`: a 64×32 sensor image tagged `.right`, with the strip look on, must come back 32×64 with its red edge at the top. Checked with B&W both on and off.

**Still needs a device:** capture in both landscape orientations, build a strip with each stock, and confirm every frame is upright.

---

## F1 — Downscale first, render in float

### What it is

`applyStripLook` currently filters the full-resolution photo for every slot on every toggle. It compensates for later downscaling by scaling the grain tile (`sizeCompensation`). v4 resizes **first** and applies every effect at output resolution.

### Design

1. Resize the upright `CIImage` to fill `outputWidth × outputWidth / cellAspectRatio` with `CILanczosScaleTransform`, then centre-crop it to the slot. The crop moves from `StripGenerator.drawAspectFilled` into `ImageProcessor`. `drawAspectFilled` stays as a no-op-safe fallback for unfiltered images.
2. Every effect then works in **output pixels**. Delete `sizeCompensation` and its comment. Grain size, halation radius and bloom radius are fractions of output width (constants).
3. Use a dedicated `CIContext` with `workingFormat: .RGBAh` and the default linear working space, so curves and glow do not band. Keep one static context; do not create contexts per render.
4. `StripViewModel.renderStrips()` cancels an in-flight render when `customization` changes again. Repeated toggles must not queue renders.

**`outputWidth` becomes required** for the strip path. Every caller already passes it.

### Acceptance

- Render time per strip measured before and after, on the simulator and on a device, and recorded in §Implementation status. Report cold and warm runs separately.
- No visual change with stock Off and B&W off: that path still returns the original image untouched.

---

# Theme B — Film model

All film maths lives in one new pure file, **`Features/Camera/FilmModel.swift`** (backend, `nonisolated`). It has no Core Image dependency, so it is fully unit-testable. Numbers live in `Constants.ImageProcessing.Film`.

## F2 — Characteristic curves (the negative)

### Background

Film responds to light as **density against log exposure**: a soft toe in the shadows, a straight-line section whose slope is the contrast (gamma), and a shoulder that compresses highlights. Colour negative has three dye layers with slightly different curves and speeds. Those differences give each stock much of its colour character and its crossovers.

### Model

For each channel c ∈ {r, g, b}, with x = log10(E) and E the scene-linear exposure (0.18 = mid grey):

```
D_c(x) = Dmin_c + (Dmax_c − Dmin_c) / (1 + exp(−k_c · (x − x0_c)))
k_c    = 4 · gamma_c / (Dmax_c − Dmin_c)        // slope at x0_c equals gamma_c
```

The logistic curve gives a toe and a shoulder automatically and is strictly increasing. `x0_c` is the per-layer speed offset. Shifting one layer's `x0` relative to the others creates the stock's crossover.

```swift
struct FilmCurve: Sendable, Equatable {
    let dMin: Double, dMax: Double, gamma: Double, x0: Double
    func density(atLogExposure x: Double) -> Double
}
struct NegativeProfile: Sendable { let r, g, b: FilmCurve; let isMonochrome: Bool }
```

For monochrome stocks, input luminance uses `Constants.ImageProcessing.Film.monoSpectralWeights`, an orthochromatic-to-panchromatic choice per stock. All three channels then use `r`.

### Input linearisation

Strip photos are already developed JPEG/HEIF (display-referred), not scene-linear RAW. Treat Core Image's linearised sRGB as relative scene exposure. Apply `Film.exposureScale` (default 1.0) so 0.18 lands on each stock's `x0`. This is an approximation and is accepted for v4. Re-developing strips from RAW is a v5 candidate.

## F3 — Print stage

### Background

A negative is never viewed directly. It is printed onto print film or paper, which has its own steeper curve. The look is the **product of two curves**. More negative density means less light reaches the print.

### Model

```
printLogE_c = −D_neg_c + printOffset_c
D_print_c   = printCurve_c.density(atLogExposure: printLogE_c)
output_c    = 10^(−D_print_c)              // linear transmittance/reflectance, then CI re-encodes
```

`printOffset_c` is **solved, not hand-tuned**. `FilmModel.balancedPrintOffsets(negative:print:)` chooses the per-channel offsets so a neutral 0.18 input comes out neutral at `Film.printMidGreyTarget` (default 0.18). Each channel needs a 1-D root find (bisection), which is unit-testable. White balance stays a creative choice of the stock's curves and does not leak from the print.

```swift
struct PrintProfile: Sendable { let r, g, b: FilmCurve }
```

Slide (reversal) film has no print stage. Its print profile is `projection`: a print whose combined response approximates identity in density. Its contrast lives in the negative curve.

### Rendering: a baked colour cube, not a shader

`FilmLUT.cube(negative:print:monochrome:dimension:) -> Data` evaluates the full negative→print chain for every lattice point. The default dimension is 64, from `Film.lutDimension`. The cube is applied with `CIColorCubeWithColorSpace` in sRGB. Results are cached by `(FilmStock, PrintStock, blackAndWhite)` in a lock-protected dictionary; there are at most 6×4×2 entries.

Why a cube and not a Metal `CIColorKernel`:

- It needs no `-fcikernel` build rules.
- The same pure Swift function that the tests check produces the pixels.
- At 64³ the lookup is exact enough for 8-bit output.

Move to a kernel only if profiling shows the cube build or lookup is the bottleneck (OPEN v4-8).

### Stocks and prints (v4 launch set)

| `FilmStock` | Label | Type | ISO | Character | Default print |
|---|---|---|---|---|---|
| `.none` | Off | — | — | Untouched (fast path) | — |
| `.daylight200` | Daylight 200 | Colour negative | 200 | Warm, medium contrast, consumer feel | `.lab` |
| `.portrait400` | Portrait 400 | Colour negative | 400 | Low contrast, wide latitude, soft skin | `.lab` |
| `.cine500T` | Cine 500T | Colour negative, tungsten | 500 | Cool, with a strong halation default | `.cinema` |
| `.slide100` | Slide 100 | Reversal | 100 | High contrast and saturation, deep blacks | `.projection` |
| `.mono400` | Mono 400 | B&W negative | 400 | Classic panchromatic | `.lab` |
| `.mono3200` | Mono 3200 | B&W negative, pushed | 3200 | Hard contrast, heavy grain | `.lab` |

| `PrintStock` | Label | Character |
|---|---|---|
| `.lab` | Lab print | Neutral, moderate contrast |
| `.cinema` | Cinema print | Contrasty, slightly cool shadows |
| `.matte` | Matte paper | Lower Dmax (lifted blacks), warm paper white |
| `.projection` | Projection | Slide film only. Hidden from the picker for negative stocks. |

All curve numbers are aesthetic starting points marked `// OPEN: v4-5`. Tune them against public manufacturer datasheet curves (published characteristic curves) and real captures. Do not take them from another app.

### Tests (`FilmModelTests`)

- Every curve is strictly increasing over x ∈ [−3, 1].
- `density(atLogExposure: x0)` is the midpoint, and the slope there equals `gamma` within 1e-6.
- `balancedPrintOffsets` maps 0.18 grey to a neutral output (|r−b| < 1/255) for every stock and print pair.
- The cube is monotonic along each channel axis for a neutral ramp, and black stays at or below white.
- For a monochrome stock, the cube output has r == g == b for every lattice point.

---

# Theme C — Physical effects

Effects are applied in this fixed order. **Order is part of the spec.**

```
upright → downscale+crop (F1) → [B&W luminance if mono or B&W toggle]
→ halation (F4, linear light, before the curve) → film cube (F2/F3)
→ bloom (F6) → light leak (F6) → grain (F5, last so grain sits on top)
```

Every random element uses a **seed derived from the strip date and slot index** (`StripGenerator` passes it in). The same strip re-renders identically. Toggling one effect does not reshuffle another.

## F4 — Halation

**Physics:** bright light passes through the emulsion, reflects off the film base, and re-exposes the red-sensitive layer, leaving a red-orange glow around highlights. Cinema stocks without an anti-halation backing show it strongly.

**Implementation** (built-in filters, all in linear light):

1. Highlight key: `max(0, L − t) / (1 − t)` with t = `Film.halationThreshold` (default 0.75), built with `CIColorMatrix` and `CIColorClamp`.
2. `CIGaussianBlur`, radius = `Film.halationRadiusFraction × outputWidth`, then cropped back to the extent.
3. Tint with `CIColorMatrix` to `Film.halationTint` (red-dominant), times the stock's `halationStrength`.
4. Add with `CIAdditionCompositing` **before** the film cube, so the glow goes through the film's shoulder like real light.

Each stock carries a default strength (Cine 500T highest). The Halation toggle switches it to 0.

**Tests:** a single white dot on black gains red energy in a surrounding ring, and red exceeds blue there. Strength 0 leaves the image pixel-identical to the no-halation path.

## F5 — Grain v2

**Physics (Newson et al., 2017, "Realistic Film Grain Rendering"):** grain is a random field of developed silver or dye clouds. Its visibility depends on local density, its size grows with film speed, and in colour film each dye layer has its own grain. A true Boolean-model Monte Carlo simulation is too slow to run on every toggle, so v4 approximates it statistically.

**Implementation:**

- Two octaves of `CIRandomGenerator` noise, fine and coarse. Each is scaled by `Film.grainSizePixels[iso]` relative to **output pixels** (F1 makes this direct) and offset by the seed.
- **Colour stocks:** independent noise per channel, mixed toward mono by `Film.grainChroma` (default 0.35). **Mono stocks:** a single channel.
- Amplitude is shaped by the **post-curve density**: `Film.grainDensityCurve`, evenly spaced control points over 0–1 density. It replaces `grainLuminanceCurve`, and the shape stays a tunable U (OPEN v4-5).
- Blend in linear light with a soft-light-style composite centred on 0.5, so the mean tone is preserved. The grain mean must not shift exposure.
- The existing ISO 100 / 400 / 3200 grain intensities become the `grainIntensity` of the new stocks by ISO.

`makeLiveGrainTile` (the viewfinder preview grain from v2 F6) is unchanged.

**Tests:**

- Grain variance increases with ISO.
- The mean of a mid-grey patch shifts by less than 1/255 with grain on.
- The same seed gives identical output and different seeds give different output.
- Variance is maximal in the band the density curve says it should be.

## F6 — Bloom and light leak

**Bloom (mist / diffusion filter look):** `CIGaussianBlur` at `Film.bloomRadiusFraction` blended back by screen at `Film.bloomStrength`. Highlights spread softly and contrast drops slightly without blurring detail. Off by default.

**Light leak:** a procedural warm gradient. Use one or two `CIRadialGradient`s in `Film.lightLeakColors` (amber or red), centred just outside a frame edge chosen by the seeded RNG, screen-blended at `Film.lightLeakStrength`. No bundled image assets. Off by default.

**Vignette:** not added at strip time. The RAW development step already applies one (OPEN v4-4).

**Tests:** both effects are pixel-identical to the off path when disabled. A light leak with a fixed seed is deterministic and only brightens (it never darkens any pixel).

---

# Theme D — Controls

## F7 — Strip and Settings UI, model and migration

### Model (`StripCustomization`, backend)

```swift
var filmStock: FilmStock = .none          // new cases, see F3 table
var printStock: PrintStock? = nil         // nil = the stock's default print
var effects: FilmEffects = .stockDefaults  // halation, bloom, lightLeak: Bool
var blackAndWhite: Bool = false
```

`FilmEffects.stockDefaults` resolves per stock: halation on for Cine 500T, and on at the stock's own strength for the others; bloom and light leak off.

**Migration** (pure, tested; follows the v2 `migrating(fromLegacyGrainEnabled:)` pattern). Stored raw values are mapped as follows (OPEN v4-6):

| Stored value | New stock |
|---|---|
| `iso100` | `.daylight200` |
| `iso400` | `.portrait400` |
| `iso3200` | `.cine500T` |
| unknown | `.none` |

**B&W toggle with a colour stock:** the image is converted to luminance first, then rendered through the stock's own curves in monochrome, keeping its grain and halation (OPEN v4-7). With a mono stock the toggle is shown on and disabled.

### StripView (frontend)

The controls card becomes:

1. Film stock picker. It replaces the ISO picker and keeps the same menu style.
2. Print picker, shown only when the stock is not Off and is not slide.
3. Effects: **Halation**, **Bloom** and **Light leak** toggles, shown only when the stock is not Off (OPEN v4-2: toggles, not sliders).
4. Black & white toggle (unchanged position).

The swatch row and the Save / Share / Archive buttons are unchanged. While re-rendering, show the existing rendering state. Do not blank the strip.

### Settings (frontend)

Under **Strip defaults**: Film stock, Print and the three effect toggles, persisted with new `Constants.DefaultsKeys`. The old `stripFilmStock` key migrates as above.

### Tests

- `FilmStockMigrationTests` extended for the new mapping.
- Default resolution: a nil print resolves to the stock's default.
- Effect defaults are correct per stock.
- A UI test opens the strip screen and cycles every stock without a crash (`frmrUITests`, simulator, PhotosPicker path).

---

## Constants additions (summary)

All in `Constants.ImageProcessing.Film` (backend namespace) unless noted:

- `lutDimension`, `exposureScale`, `printMidGreyTarget`, `monoSpectralWeights`
- Per-stock `NegativeProfile` values, per-print `PrintProfile` values, ISO, `grainIntensity`, `halationStrength`
- `halationThreshold`, `halationRadiusFraction`, `halationTint`
- `grainSizePixels` (by ISO), `grainChroma`, `grainDensityCurve`
- `bloomRadiusFraction`, `bloomStrength`, `lightLeakColors`, `lightLeakStrength`
- `Constants.DefaultsKeys`: `stripPrintStock`, `stripHalation`, `stripBloom`, `stripLightLeak`
- Frontend `Constants.StripUI`: any new row metrics

Remove: `grainLuminanceCurve` (superseded by `grainDensityCurve`), the `FilmStockProfile.colourMatrix` casts (superseded by curves), and `sizeCompensation`. Delete tests that only covered superseded behaviour **after** their replacements pass. The `warmStocksPushRedAboveBlue…` test becomes a curve-based equivalent.

## New files summary

| File | Owner | Purpose |
|---|---|---|
| `Features/Camera/FilmModel.swift` | backend | `FilmCurve`, `NegativeProfile`, `PrintProfile`, print balancing, `FilmLUT` cube builder and cache |
| `frmrTests/FilmModelTests.swift` | backend | Pure model tests (F2/F3) |
| `frmrTests/FilmEffectsTests.swift` | backend | Halation, grain, bloom and light-leak tests (F4–F6) |
| `frmrTests/StripLookRegressionTests.swift` | QA | Orientation and determinism regressions across all stocks |

## Open decisions introduced by v4

| # | Decision | Default until resolved |
|---|---|---|
| v4-1 | Number and names of launch stocks | The six in §F3 |
| v4-2 | Effect controls: toggles or strength sliders | Toggles (minimalist) |
| v4-3 | Light leak randomness | Fixed per strip (seed from date and slot) |
| v4-4 | Strip-time vignette | None; the RAW development vignette only |
| v4-5 | Curve, grain and halation numbers | Aesthetic estimates; calibrate on device against real captures and public datasheet curves |
| v4-6 | Legacy ISO → stock mapping | Table in §F7 |
| v4-7 | B&W toggle on a colour stock | Monochrome through the stock's curves |
| v4-8 | Cube vs Metal `CIColorKernel` | Cube; switch only if profiling demands it |

All earlier open items (project.md §13/§14, v2-1…v2-5, v3 carry-forward) remain open and untouched.

---

## Sequencing recommendation

Work strictly in this order. Each step builds and passes all tests before the next starts.

1. **F0**: done. Run the device check when a device is available.
2. **F1**: downscale-first and float context. Measure render time before and after.
3. **F2 + F3**: `FilmModel.swift` and its tests first, with no Core Image. Then the cube and its cache, then wire them into `applyStripLook` behind the existing ISO stocks so the UI does not change yet.
4. **F7 model and migration** (backend): new enums, defaults and migration tests.
5. **F4, F5, F6**, in that order, each with its tests.
6. **F7 UI** (frontend): StripView and Settings, against the finished model.
7. **QA pass**: the regression suite, a constraint audit (`scripts/frmr-guard.sh --all`, if present), and a device checklist.

Backend steps 2–5 are sequential, in one context. Frontend step 6 can start once step 4's model API is merged; it must not touch pipeline files.

## Definition of done (v4)

- [ ] All v1–v3 definition-of-done criteria still pass (no regressions)
- [ ] No photo in a strip is ever rotated relative to its unfiltered render, for any stock, print, effect or B&W combination (test plus device photograph)
- [ ] No `CIImage(image:)` remains on a photo path
- [ ] Re-rendering the same strip is pixel-identical
- [ ] Render time per strip recorded before and after, cold and warm, simulator and device
- [ ] Every `// OPEN:` in v4 files is marked in code, with its value in `Constants.swift`
- [ ] No force-unwraps in production paths; errors surface through `AppError`; cosmetic filter failures fall back to the unfiltered photo and are logged
- [ ] New pure logic has tests (`FilmModelTests`, `FilmEffectsTests`, migration and regressions)
- [ ] Superseded constants, casts and tests are removed
- [ ] Compiles without warnings
- [ ] `CLAUDE.md` "Current build status", `project.md` §14 and §8, and `README.md` are updated

---

## Handoff

Per `CLAUDE.md` §Working with other agents. Two implementers and one verifier. Each needs `CLAUDE.md`, `project.md`, `frmr-v2-spec.md` and this file.

**Agent: frmr-backend**

```
You are working on v4 Themes A–C and the F7 model in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md        — engineering rules and constraints
2. project.md       — full product specification
3. frmr-v2-spec.md  — v2 grain and film stocks (F4–F6)
4. frmr-v4-spec.md  — this document
5. .claude/skills/ios-camera-orientation/SKILL.md

Situation:
  DONE:    F0 (orientation fix + tests)
  DOING:   nothing
  BLOCKED: none — v4-1…v4-8 use the documented defaults, marked OPEN
  NEXT:    F1, then F2+F3 (FilmModel.swift + tests before any Core Image),
           then the F7 model + migration, then F4, F5, F6. Build and run
           frmrTests after each feature.

Deliverable: a diff per feature, render-time measurements for F1, and passing
FilmModelTests / FilmEffectsTests. Record status in frmr-v4-spec.md
§Implementation status (propose text; the lead commits docs).

Do not add dependencies. Do not make network calls. Never call CIImage(image:)
on a photo. Do not resolve OPEN: items by guessing — flag them and use the
placeholder pattern.
```

**Agent: frmr-frontend** (after the backend F7 model is in)

```
You are working on v4 F7 UI (StripView + Settings) in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md, 2. project.md, 3. frmr-v4-spec.md (§F7)

Situation:
  DONE:    FilmStock / PrintStock / FilmEffects model and defaults keys (backend)
  DOING:   nothing
  BLOCKED: v4-2 (toggles vs sliders) — use toggles, mark OPEN
  NEXT:    StripView controls card per §F7, then Settings strip defaults.

Deliverable: a diff for StripView, SettingsView and Constants.StripUI, with
accessibility labels on every new control. You do not touch ImageProcessor,
FilmModel, StripGenerator or Models/*. Use a CONTRACT REQUEST for anything else.
```

**Agent: frmr-qa** (after each theme lands)

```
Verify frmr v4 black-box against frmr-v4-spec.md §Definition of done.
Write StripLookRegressionTests (orientation for every stock × B&W × effects,
determinism, Off fast-path identity). Run frmrTests and frmrUITests on simulator
id 1B3A9DB6-1D5A-4447-9849-CF49C94A5FC8. File bugs in qa/bugs/. Do not fix
production code. List device-only checks explicitly as unverified.
```

---

## Implementation status — v4 build

| Feature | Status |
|---|---|
| F0 Orientation fix | ✅ Code and unit tests (2026-10-20). Device check pending. |
| F1–F7 | Not started |

## References

- Newson, Faraj, Galerne, Delon, *Realistic Film Grain Rendering*, IPOL 2017 — https://www.ipol.im/pub/art/2017/192
- Zhang, Wang, Tian, Pappas, *Film Grain Rendering and Parameter Estimation*, ACM TOG 2023 (analytical, real-time follow-up)
- agx-emulsion: an open spectral negative and print simulation, for model background only; no code or data is used — https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209
- Apple, WWDC20 *Build Metal-based Core Image kernels with Xcode* (only if v4-8 flips) — https://developer.apple.com/wwdc20/10021
