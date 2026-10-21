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
| F1 Downscale-first, float pipeline | ✅ (2026-10-20). Slot resize and crop in `ImageProcessor`, static RGBAh strip context, `sizeCompensation` removed, superseded renders cancelled (generation counter). Simulator, one strip of 4 × 12 MP photos: before, cold 2.7 s / warm 2.0 s; after, cold ~0.45 s / warm ~0.10 s. Device timing pending. |
| F2 + F3 Curves and print stage | ✅ `FilmModel.swift` (logistic curves, bisection print balancing, 64³ sRGB cube) applied through `CIColorCubeWithColorSpace`; 14 `FilmModelTests`. **Deviation:** the cube cache is capped at `Film.lutCacheLimit` (8) with FIFO eviction, because 48 × 4 MB cubes would use ~190 MB. **Finding (v4-5):** with x0 at mid grey, diffuse white prints at ~223/255 and deep shadows compress. Lead decision: add an output white/black-point normalisation (see F2/F3 follow-up in the F4–F6 round). |
| F7 model and migration | ✅ `FilmStock` (six stocks plus Off), `PrintStock`, `FilmEffects`, resolved print, defaults keys, v2→v4 migration (on load, on decode, and in place at launch in `AppEntry`). Views compile unchanged. |
| v4-5 tone follow-up | ✅ `OutputNormalisation`: input white prints at `printWhiteTarget` (0.96 sRGB) and each print keeps its own black, with one neutral-preserving map per stock and print. Daylight 200 + Lab: 0.1 → 24/25/27, 0.2 → 38/40/43, 0.46 → 129, 0.8 → 226/221/215, 1.0 → 249/244/239. Mid grey stays neutral but no longer sits at 0.18. |
| F4 Halation | ✅ Highlight key → blur (1.2% of slot width) → red-orange tint × stock strength (Cine 500T 0.9), added with `linearDodgeBlendMode` in linear light before the cube. (`CIAdditionCompositing` turned an alpha-0 glow black after premultiply.) 5 tests. |
| F5 Grain v2 | ✅ Two seeded octaves, chroma 0.35 for colour stocks, mono grain for mono stocks and B&W, amplitude from print density, multiplicative and mean-preserving. Seed = `StripGenerator.seed(for:slot:)` (SplitMix64; `Hasher` is per-process random). `grainLuminanceCurve` and `FilmStockProfile` removed. 11 tests. |
| F6 Bloom and light leak | ✅ Screen-blended blur bloom; seeded procedural two-glow leak placed outside a frame edge. Both off by default and never darken. 6 tests. |
| Timing after F4–F6 | Simulator, 4 × 12 MP strip: warm ~80 ms with or without effects; process-cold ~450 ms. Device pending. |
| F7 UI | ✅ StripView controls card: stock; print when `isPrintPickerVisible`; Effects toggles when `areEffectsVisible`; B&W bound to `blackAndWhiteToggle` and disabled for mono stocks; rows fade over `StripUI.controlRowAnimationDuration`. Settings → Strip defaults: stock; print ("Stock default" plus the stock's prints, shown only when `FilmStock.hasPrintChoice`); three effect toggles with halation defaulting on. Accessibility hints on every new control. Settings screenshots in `qa/screenshots/v4/`. **Pending:** the strip screen has never been seen running, because PhotosPicker can't be driven headlessly. Needs QA on an interactive simulator or a device. |
| Contract `FilmStock.hasPrintChoice` | ✅ Added by the lead. Used by `StripViewModel.isPrintPickerVisible` and SettingsView. |
| QA pass 1 | `StripLookRegressionTests` (9) added; 136 tests pass. Findings: BUG-V4-1 (v4-4/v4-8 not marked) and BUG-V4-2 (fallbacks not logged), both backend; BUG-V4-3 (no strip-screen UI test) and OBS-V4-4 (Settings toggles inconsistent with the strip screen), both frontend; OBS-V4-5 (seeds repeat across strips; lead decision: fix); DOC-V4-6 (docs, fixed by the lead). Fixes in progress. |
| QA fixes | ✅ BUG-V4-1 (`stripVignetteEnabled` / `usesColourCube` decision flags, OPEN v4-4/v4-8), BUG-V4-2 (every effect fallback logs through `skipping(_:_:)`), OBS-V4-5 (seed by global frame index, so strip 0 is unchanged), OBS-V4-4 (Settings hides effects for Off and locks B&W for mono stocks; `FilmStock.hasEffects` added by the lead), DOC-V4-6 (docs updated). BUG-V4-3: `frmrUITests/StripScreenUITests` written; it drives PhotosPicker after `simctl addmedia qa/fixtures/*` and passed for the frontend agent. The lead's re-run was stopped at the user's request; the user is testing the strip screen by hand. Strip-screen labels fixed (`StripPickerRow`). |
| Final lead check | 138 frmrTests pass, zero Swift warnings, guard clean (30 OPEN warnings). The device checklist below is still outstanding. |

Verified by the lead after F7: 127 frmrTests pass (`-parallel-testing-enabled NO`; parallel simulator clones fail to clone here), zero Swift warnings, guard clean (28 OPEN warnings).

Verified by the lead: 102 frmrTests pass, zero Swift warnings, `frmr-guard --all` clean.

## References

- Newson, Faraj, Galerne, Delon, *Realistic Film Grain Rendering*, IPOL 2017 — https://www.ipol.im/pub/art/2017/192
- Zhang, Wang, Tian, Pappas, *Film Grain Rendering and Parameter Estimation*, ACM TOG 2023 (analytical, real-time follow-up)
- agx-emulsion: an open spectral negative and print simulation, for model background only; no code or data is used — https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209
- Apple, WWDC20 *Build Metal-based Core Image kernels with Xcode* (only if v4-8 flips) — https://developer.apple.com/wwdc20/10021

---

# Part 2 — Film at capture (added 2026-10-20)

**Folded into v4 at the user's request** (originally drafted as a separate v5 spec). It builds on Part 1 above. Feature numbers continue at F8, and open decisions continue at v4-9.

## Part 2 overview

Part 2 moves the film choice to where the photo is taken. Each photo carries its own stock, and the strip becomes plainer.

| # | Feature | Summary |
|---|---|---|
| F8 | Plain strip | White or black background only. No sprocket holes, frame numbers or sideways edge date. Photos, captions and the bottom date stamp stay. |
| F9 | Film stock on the camera, with live preview | A film stock control on the camera screen, in both Diary and Film strip modes. The viewfinder shows the stock's colour and tone live. |
| F10 | Diary review step | After a diary capture: the photo in its stock, a stock row to change it, **OK** (bottom left) and **Retake** (bottom right). OK leads to the prompt screen. |
| F11 | Per-photo stock (non-destructive) | Entries and photobooth shots keep the **original** photo plus their stock. The look is applied when showing or rendering. |
| F12 | Strip "As shot" with override | The strip's stock picker defaults to **As shot** (each frame keeps its own stock) and can override all frames with one stock. |

## Decisions made by the user (2026-10-20)

| Question | Decision |
|---|---|
| Test photos | The user's 5 iPhone 15 Pro Max DNGs (3024×4032) are loaded into the simulator's Photos library only. **Not** in the repo. |
| What stays on the plain strip | Photos, captions and the bottom date stamp. Holes, frame numbers and the edge date go. |
| Camera stock control | **Live preview in the viewfinder** |
| Live preview fidelity | **Colour and tone only** (the film cube). Grain, halation, bloom and light leak appear only on the captured photo. |
| Diary photo storage | **Keep the original plus the stock** (non-destructive) |
| Strip stock picker | **Strip overrides**, defaulting to "As shot" |
| Diary review controls | Stock row, Retake (bottom right), OK (bottom left). Print and effects use the stock's defaults. |
| Camera stock in Film strip mode | **Yes, both modes** |

---

## F8 — Plain strip

- `StripBackground` becomes `white` and `black` only. Remove `cream` and `custom(Color)` and the swatches that set them.
  - The stored default `"cream"` migrates to `white`.
  - The swatch row shows two swatches.
  - Settings → Background offers White and Black.
- `StripGenerator`: stop drawing sprocket holes, frame numbers and the rotated edge date. **Delete** that code and its constants (`sprocketHole*`, `frameNumber*`, `edgeDate*`, `datestampRotationDegrees`), and remove the frame-number gutter from the caption width.
  - Keep the white paper border only if it still reads well on black. Default: no separate paper border; the background fills the strip (OPEN v4-9).
- Caption and date text colour come from `contrastingTextColor` (cream on black, near-black on white).
- **Tests:**
  - Update `StripGeneratorTests`. Delete `sprocketHolesArePunchedIntoBothPaperBorders`, `paperBorderStaysWhiteBetweenSprocketHoles` and `frameNumbersArePrintedInAmberInTheReservedGutter`.
  - Add `plainStripHasNoMarksOutsidePhotosAndText`: background pixels are uniform outside the photo, caption and date rects.
  - Add a background migration test.
  - QA's `StripLookRegressionTests` must still pass. If one only asserted strip decoration, QA updates it.

## F9 — Film stock on the camera, live preview

### Control

A **Film** control in the camera chrome, following the v3 rotate-in-place rules (`ios-camera-orientation` skill):

- It is collapsed by default to one 44pt chip with a film SF Symbol and a short code (`OFF`, `D200`, `P400`, `C500`, `S100`, `M400`, `M3.2K`).
- Tap expands a row of stock chips, like the collapsible white balance from v3 F10, and opening one collapses the other.
- Glyphs rotate; backings do not. It appears in **Diary and Film strip modes**.
- The selection lives in `CameraViewModel.filmStock`. It persists as a new default (`DefaultsKeys.cameraFilmStock`, default `.none`) and is separate from the strip defaults (OPEN v4-10).

### Live preview (colour and tone only)

The current viewfinder is an `AVCaptureVideoPreviewLayer`, which cannot be filtered. Replace it for the live look:

- Add an `AVCaptureVideoDataOutput` on the session queue (BGRA, `alwaysDiscardsLateVideoFrames = true`).
- Render frames through the **same film cube** as the strip, `FilmLUT`, with `CIColorCubeWithColorSpace`, into an `MTKView` using one `CIContext(mtlDevice:)`.
  - Cache the cube per stock; it is already cached in `FilmLUT`.
  - With stock Off, skip the cube.
- **Orientation rules stay exactly as v3/post-v3:** the interface is portrait-locked, and the preview is never re-angled to the horizon. Set the data-output connection's `videoRotationAngle` to the portrait preview angle **once**, not per device turn. Capture rotation via `RotationCoordinator` is unchanged.
- **Tap to focus and expose currently uses `previewLayer.captureDevicePointConverted`.** Keep a hidden `AVCaptureVideoPreviewLayer` for coordinate conversion only (simplest and proven), or convert manually from the aspect-fill mapping. The decision and a unit test of the mapping are required. Pinch, swipe-EV and the focus indicator must behave exactly as before.
- **Performance target:** 30 fps or better on an A15 or newer, with no thermal warning after 2 minutes. Measure on a device. If it is missed, fall back to the plain preview layer when stock is Off, and note it.
- The front camera preview stays mirrored as today.

### Capture

The stock chosen at the moment of capture is stored with the shot (F11). The captured photo itself is still developed exactly as today (RAW → `ImageProcessor.process`). **The stock is not baked in.**

## F10 — Diary review step

New screen `DiaryReviewView` (frontend) with its logic in `DiaryReviewViewModel` or `CameraViewModel` (backend). It is presented after a diary capture and **before** `EntryEditorView`:

- **Photo:** the captured photo rendered through its stock, using full v4 `applyStripLook` with the stock's default print and effects at screen size. While the RAW develops, show the JPEG preview through the same look, then swap it, as today.
- **Stock row:** horizontal chips under the photo for all 7 stocks (Off plus six), starting from the camera's current stock. Changing a chip re-renders the photo (debounced, last request wins).
- **Buttons:** **OK** at the bottom left (primary style) and **Retake** at the bottom right (secondary).
  - OK stores the chosen stock with the pending photo and presents the existing prompt screen (`EntryEditorView`).
  - Retake discards the capture and returns to the camera.
- The prompt screen is unchanged. Its Retake and Skip still work, and its header photo shows the chosen look.
- No print or effects controls on this screen. They use stock defaults (user decision).

## F11 — Per-photo stock (non-destructive)

- `DiaryEntry` gains `filmStockRaw: String?`. This is a SwiftData lightweight migration: an optional property, so existing rows read nil, which means Off. Add an accessor `filmStock: FilmStock` that falls back to `.none`.
- The **original** developed photo is saved as today (`photoPath`). Nothing film-processed is written over it.
- Display: `DiaryView` thumbnails, `EntryDetailView` and the editor header show the photo through its stock.
  - Render off the main thread at display size.
  - Cache rendered images in memory keyed by (entry id, stock, size).
  - Do **not** persist rendered copies in v4 (OPEN v4-11).
- Photobooth shots carry their stock:
  - `PhotoboothViewModel.shots` becomes `[(image, stock)]` (a small struct).
  - Camera captures take the camera's current stock.
  - **Gallery picks take the camera's current stock at pick time** (OPEN v4-12).
- `StripItem` gains `filmStock`.
- Changing an entry's stock after saving is **not** in v4 (OPEN v4-13).

## F12 — Strip "As shot" with override

- `StripCustomization` gains `stockOverride: FilmStock?`. **nil means "As shot":** each frame renders with its own stock, using that stock's default print. The existing `filmStock` field is renamed to `stockOverride`, or kept and documented. Pick one and remove the other; no aliases.
- **Strip screen Film stock picker:** "As shot" plus the 7 stocks. Default: As shot.
  - **Print picker:** shown only when an override stock with a print choice is selected. As-shot frames use their own default prints.
  - **Effects toggles and B&W:** stay strip-level and apply to every frame. Effects are hidden only when every frame's effective stock is Off.
- **Settings → Strip defaults:** the Film stock default gains "As shot", which becomes the new default. Existing stored v4 values stay as overrides.
- `StripGenerator` renders each cell with its effective stock: the override if set, otherwise the frame's own. Seeds are unchanged (global frame index).
- **Tests:**
  - As shot renders each frame with its own stock.
  - An override replaces every frame's stock.
  - Effects visibility with mixed stocks.
  - Settings default migration.

---

## F13 — Download from the diary review screen (added 2026-10-20)

**User decisions:**

| Question | Decision |
|---|---|
| What is saved | The photo **with the full film look**: the chosen stock, its default print and effects, and grain, at full resolution, saved as HEIC to the camera roll |
| After saving | **Stay on the review screen** with a brief "Saved" confirmation. The user can still tap OK to write an entry, change the stock, or Retake. |
| Diary entry | **None.** Download alone adds nothing to the diary or library. An entry exists only if the user also taps OK. |
| Placement | **Top right**: a download icon over the photo. The bottom row stays OK (left) and Retake (right). |

**Behaviour:**
- **The control:** an SF Symbol button (`arrow.down.to.line` or similar) at the top right of `DiaryReviewView`, at least 44pt, with an accessibility label. It is disabled while the photo is rendering or saving.
- **Rendering:** a new backend entry point renders the pending photo at **full resolution** through the full v4 chain (not the slot-sized strip path).
  - Proposed signature: `ImageProcessor.renderFullLook(of:stock:seed:) -> UIImage`. It applies the stock's default print and effects; the seed is derived from the capture time.
  - It saves through the existing `PHPhotoLibrary+Save` path (permission check, `AppError` on failure), as HEIC with the orientation tag preserved.
  - Off saves the plain developed photo.
- **Waiting for the RAW:** if the RAW is still developing, Download waits for it, so the JPEG preview is never what gets saved.
- **Saving again:** downloading again after changing the stock saves another photo. That's intentional: each tap saves one photo. A Retake after Download does not remove the saved photo (OPEN v4-15: should a second Download of the *same* stock be blocked?). Default: allow it.
- **Tests:**
  - backend: the full-resolution render keeps the source size and orientation, Off returns the developed photo, and the same seed gives an identical result.
  - frontend/QA: the UI test taps Download on the review screen and checks the "Saved" state appears and OK still works.

## F14 — Stock calibration from real-film references (added 2026-10-20)

Research and evidence: `research/v4-film-reference-calibration.md`. The user approved **all** stock changes in §1 of that note, applied **after** the shadow and black-point fix:
- **Daylight 200:** more yellow-orange warmth in mids and highlights, a little more contrast and saturation, teal-leaning blues.
- **Portrait 400:** lower gamma, less saturation, gentler shoulder, warm skin bias. Visibly softer than Daylight 200.
- **Cine 500T:** teal/cyan shadow crossover (not blue-purple); warm highlights stay warm; halation stays on bright points.
- **Slide 100:** most saturated stock (reds, oranges, greens), slight warm-magenta bias, deepest black.
- **Mono 400:** black fix plus a small midtone contrast increase.
- **Mono 3200:** finer grain structure (less weight on the coarse octave), less grain in bright, low-density areas, deep blacks.

**Tests** (measurable proxies):
- Daylight 200 is warmer than Portrait 400 at mid and highlight.
- Portrait 400's effective gamma is below Daylight 200's.
- Cine 500T's shadow hue falls in the teal range.
- Slide 100's saturation is at least that of every other stock.
- Mono 3200 has lower grain variance in highlights than in midtones.

**Evidence:** re-render the user's 5 DNG sheets before and after (outside the repo).

## F15 — Photobooth strip realism (added 2026-10-20)

**User decisions:** apply **booth layout**, **portrait frames** and **real paper tone**. *Not* booth character (per-frame exposure variation and marks). **Captions stay under each frame.**

- **Booth layout:** a thin even border and thin gaps; frames nearly touching. Because captions stay, each frame gets a slim caption band directly under it, and the gap is only between the caption band and the next frame. No extra margins. Exact proportions go in `Constants.Strip` (OPEN v4-16).
- **Portrait frames:** cell aspect about 4:5 (taller than wide), replacing square, with slightly rounded frame corners (small radius constant). `drawAspectFilled` / slot cropping follow the new aspect.
- **Real paper tone:** `StripBackground.white` becomes a warm off-white paper tone and `.black` a near-black, each with a faint deterministic paper texture (very low amplitude, seeded by the strip date). Caption and date text colours stay contrasting.
- **Tests:**
  - Cell aspect is 4:5.
  - Gaps and border equal their constants.
  - Paper is neither pure white nor pure black, and its texture is deterministic.
  - QA's orientation and determinism suites still pass.
  - Plain-strip "no marks" test updated for the texture tolerance.

## Ownership and sequencing

| Step | Owner | Work |
|---|---|---|
| 1 | backend | F8 generator and model plus F11 models (`DiaryEntry.filmStockRaw`, photobooth shot struct, `StripItem.filmStock`) plus F12 model and generator, with tests |
| 2 | backend | F9 live preview engine: video data output, film cube renderer, coordinate-conversion decision with a test, `CameraViewModel.filmStock` and its default |
| 2 ∥ | frontend | F8 swatches and Settings background, F12 strip picker "As shot" (needs step 1) |
| 3 | frontend | F9 camera Film control (needs the step 2 API) and F10 `DiaryReviewView`, with the flow wired through the ViewModel API backend provides |
| 4 | qa | Regression: plain strip, per-photo stocks, As shot vs override, review flow UI test using the simulator Photos (the user's DNGs are there; do not copy them into the repo), orientation matrix unchanged |

Build folders: `build/backend`, `build/frontend`, `qa/DerivedData`. Run tests with `-parallel-testing-enabled NO`.

## Open decisions introduced by Part 2

| # | Decision | Default |
|---|---|---|
| v4-9 | Separate white paper border on a black strip | None; the background fills the strip |
| v4-10 | Camera stock default shared with the strip default? | Separate (`cameraFilmStock`, default Off) |
| v4-11 | Persist rendered display copies of entries | No, in-memory cache only |
| v4-12 | Stock for gallery-picked photobooth photos | The camera's current stock at pick time |
| v4-13 | Change an entry's stock after saving | Not in v4 |
| v4-14 | Live preview below 30 fps on older phones | Keep the cube preview and note it; revisit after device measurement |
| v4-15 | Block a repeat Download of the same photo and stock | Allow; each tap saves one photo |
| v4-16 | Booth strip proportions (border, gap, caption band, corner radius) | Thin border and gap, slim caption band; tune visually |

## Definition of done (Part 2)

- [ ] All v1–v4 criteria still pass. The v4 orientation and determinism tests still pass.
- [ ] Strip has no holes, numbers or edge date; white and black backgrounds only; cream migrates to white
- [ ] Camera Film control works in both modes and follows the rotate-in-place rules
- [ ] Viewfinder shows the stock's colour and tone live. Tap-to-focus, pinch, swipe-EV and the focus indicator are unchanged. Frame rate measured on a device.
- [ ] Diary: capture → review (stock row, OK bottom left, Retake bottom right) → prompt → save. The original photo is saved along with the stock.
- [ ] Entries and thumbnails display in their stock; old entries show as Off
- [ ] Strip As shot / override behaves per F12; Settings default is "As shot"
- [ ] Review screen Download (top right) saves the full-resolution film-look photo to the camera roll, stays on review, creates no entry, and OK still works afterwards
- [ ] No force-unwraps; errors via `AppError`; every number in Constants; OPEN markers in place; zero warnings; guard clean
- [ ] Docs: `CLAUDE.md` status, `project.md` (screens, §8, §10), `README.md`

## Implementation status — Part 2

| Feature | Status |
|---|---|
| Test photos | ✅ 5 DNGs added to simulator iPhone 17 Pro (`1B3A9DB6-…`) Photos, 2026-10-20 |
| F8 Plain strip | Backend ✅: holes, frame numbers and edge date removed; `Constants.Strip.drawsPaperBorder = false` (OPEN v4-9); white/black with cream → white migration at launch. Frontend ✅: two swatches (White/Black) with labels, the selected trait and 44pt targets; Settings Background is White/Black, default white; no `.cream`/`.custom` left in views (backend deleting the interim cases). UI-tested; screenshots in `qa/screenshots/v4/part2/`. |
| F11 Per-photo stock | Models ✅: `DiaryEntry.filmStockRaw` (+ `filmStock`; lightweight migration, old rows = Off), `PhotoboothShot`, `StripItem.filmStock`, `saveEntry(image:filmStock:includeText:context:)`, `loadPickerSelection(filmStock:)` (OPEN v4-12). Display rendering and cache not started. |
| F12 As shot / override | Model, generator and ViewModel ✅: `filmStock: FilmStock?` (nil = As shot), `stockChoices`, `label(forStockChoice:)`, Settings sentinel `"asShot"`, `effective(forFrameStock:)`. Frontend ✅: strip picker shows As shot + 7 stocks (default As shot); Settings default As shot via the `asShot` sentinel, with print, effects and B&W rules matching the strip screen. `StripScreenUITests` 2/2 pass. A test-only shim keeps QA's file compiling until QA updates line 172. |
| Lead check after step 1 | 156 frmrTests pass, zero Swift warnings, guard clean (33 OPEN). |
| F9 Film stock on camera | Backend ✅: `CameraViewModel.filmStock` + `FilmStock.shortCode`, collapsible list (one list open at a time with WB), separate persisted default (OPEN v4-10). Live preview engine: `AVCaptureVideoDataOutput` (portrait angle set once per connection, front camera mirrored) → `FilmPreviewRenderer` (aspect-fill, then the strip's cached cube, one Metal `CIContext`, 30 fps cap, OPEN v4-14) → `FilmPreviewView` laid over the existing preview layer, which still converts taps (aspect-fill unit-tested against `AVMakeRect`). Off disables the frame output. Frontend: chip and embedding. Device: fps, thermal, mirroring, tap alignment. |
| F10 Diary review | Backend ✅: `DiaryReviewViewModel` (JPEG → RAW swap, debounced stock re-render, display-size render) and `CameraViewModel.review` / `confirmReview()` / `retake()` / `pendingDiaryStock` / `pendingDiaryDisplayImage`. `Constants.Diary.presentsReviewStep = false` until the view lands. Frontend: `DiaryReviewView` and passing the stock to `saveEntry`. |
| F11 display | Backend ✅: `DiaryViewModel.displayImage(for:size:scale:)` / `cachedDisplayImage`, in-memory `FilmLookCache` (96 MB, OPEN v4-11). Display failures fall back to the original and are logged (no alert, by design). Frontend: thumbnails, detail view and editor header. |
| F13 Download | Backend ✅: `ImageProcessor.renderFullLook(of:stock:seed:coveringPixelSize:) throws` (new `AppError.filmLookRenderFailed`), `heicData`, `PHPhotoLibrary.saveToCameraRoll(photoData:)`; `downloadReview()` waits for the RAW and never creates an entry; repeat allowed (OPEN v4-15). Simulator: 12 MP render ~0.6–0.85 s + HEIC ~0.2 s. Frontend: top-right button and "Saved" state. |
| Download grain scaling (lead decision) | ✅ `renderFullLook` scales grain by upright width ÷ `Film.grainReferenceWidth` (1080, OPEN v4-5), so Download keeps the review's grain-to-frame proportion. Strip renders are byte-identical. Test `downloadGrainMatchesTheReviewRenderAtReviewSize` (±35%). |
| Lead check after backend step 2 + frontend F8/F12 | 183 frmrTests pass, zero Swift warnings, guard clean (37 OPEN). |
| F9/F10/F11/F13 UI | Frontend ✅: `FilmStockControl` (44pt chips, rotating glyph, short codes) in both modes and both chrome layouts; `FilmPreviewView` overlaid on the preview with hit testing off; `DiaryReviewView` (scrolling stock row, OK bottom left, Retake bottom right, Download top right with spinner and "Saved"), shown in a single diary-flow cover; `presentsReviewStep = true`; editor header uses the chosen look and saves pass the stock; `EntryLookImage` for thumbnails and detail. `DiaryReviewUITests` 4/4 through a DEBUG-only `-UITestDiaryReview` fixture. Device-only: live viewfinder, real capture → review, real camera-roll save. |
| Lead check after frontend Part 2 UI | 184 frmrTests pass, zero Swift warnings, guard clean (36 OPEN). |
| Real-photo stock check (lead) | `frmrTests/FilmStockSampleSheetTests` (skipped unless `FRMR_FILM_SAMPLES_DIR`/`_OUT` are set) rendered the user's 5 DNGs (kept outside the repo). Highlights and colour fine. **Shadows fail:** every print lifts black to ~20/255 and compresses everything below ~20% input; low-key photos (IMG_3530) turn to flat grey. User approved the fix (deeper per-print blacks, softer toe). Reference-image calibration research in progress. |
| F13 Download from review | See the backend and frontend rows |
| Shadow / black-point fix | ✅ Per-print `blackTarget` (Lab 6, Cinema 4, Projection 3, Matte 28 /255) in one neutral-preserving affine `OutputNormalisation`, plus a per-channel `ShadowToe` below a mid-grey pivot (0.18 linear, exponent 8; mid grey and above untouched). Daylight 200/Lab at inputs 0/0.05/0.2: 6.0/18.4/55.8 (was 20.2/22.0/39.8). Shadow separation vs Off over inputs 0.02–0.2: 0.77–1.05 per stock. 187 frmrTests (agent-reported). Lead checked sheets-v2: IMG_3530 readable on every stock, deep blacks. |
| F14 Stock calibration | ✅ Per-stock `ColourMatrix` (rows sum to 1, so neutrals, blacks and the toe are unaffected) plus per-stock `GrainProfile`. Measured: Daylight warmth +13/+16 at mid/highlight, γ 1.20; Portrait γ 0.99, saturation 0.39; Cine shadow hue 172–179° (teal, was 246°); Slide the most saturated (0.68); Mono 400 γ 1.32; Mono 3200 highlight grain below the midtones'. `FilmCalibrationTests` (5). 192 frmrTests (agent-reported). Lead compared sheets-v3 with v2: accepted. User decisions: Portrait 400 sky nudged from lavender to pastel cyan ✅ (`blueIntoGreen(0.05)` before its saturation; deep-sky hue 223.0° → 219.8°, now below Off's 222.4°; test `portraitSkiesStayCyanNotLavender`; 198 frmrTests, agent-reported; lead checked sheets-v4); Daylight 200 turquoise horizon kept as is. |
| F15 Strip realism | ✅ Backend: border 6pt, `frameGap` 4pt, 4:5 frames (`cellAspectRatio` 0.8) with `frameCornerRadius` 2.5pt, one-line caption band under each frame (`boothCaptionLines` 1, confirmed by the user), paper tones `paperWhite` ≈ #F4F0E7 / `paperBlack` ≈ #171614 with ±0.012 deterministic texture seeded by date and strip index (OPEN v4-16). `BoothStripTests` (4); gated `StripSampleRenderTests`. 197 frmrTests (agent-reported). Lead looked at the sample strips on both papers: accepted. Frontend ✅: `FilmStripCell` uses `boothCaptionLines` and the 4:5 slot with `frameCornerRadius`; StripView, Library thumbnail and StripDetailView are aspect-fit to the rendered image (screenshots: no crop or squash); swatches readable on the new papers in light and dark (the dark-mode near-black swatch only just, via its rim). The UI test archives a strip and checks Library and the detail viewer. |
| Lead check after F15 and the Portrait tweak | 198 frmrTests pass, zero Swift warnings, guard clean (39 OPEN). |
| QA pass 2 (Part 2) | Guard clean; Debug and Release builds with zero warnings; **215 frmrTests** (+17 `FilmAtCaptureRegressionTests`) and **6/6 UI tests** pass. Audit clean: no force-unwraps; the DEBUG fixture is absent from Release; no brand names in app code; no DNGs in the repo. Findings: BUG-V4-9 (v4-13 not marked) and OBS-V4-7 (entry display seed differs from review/Download) ✅ fixed by backend (`DiaryEntry.capturedAt` + `lookSeedDate`, `StripGenerator.photoLookSeed`, v4-12/v4-13 flags); the lead wired `capturedAt` into `EntryEditorView`; DOC-V4-8 (docs) ✅ fixed by the lead; test-only shim removed. |
| **Final lead check (2026-10-21)** | **218 frmrTests pass, DiaryReviewUITests 4/4, zero Swift warnings, guard clean (40 OPEN).** Device checklist (QA pass 1 and pass 2) outstanding. |
