# How frmr's film simulation works

A guide for agents and developers who need to understand, tune or extend the film look. It describes the code as of v5.2 (branch `v5.2-makeover`; v5.2 added exposure, §3, §4.3). If you change the pipeline, update this file in the same change.

**Who owns it:** the pipeline is **backend-owned** (see the ownership map in `CLAUDE.md`). Frontend only binds to `FilmLook` / `StripCustomization` values and never touches the maths.

---

## 1. The idea in one paragraph

frmr does not apply a filter or a LUT someone designed. It **simulates the photographic chain**:
1. The photo is treated as light hitting a **colour negative**: three dye layers, each with its own response curve.
2. That negative is **printed** onto a print stock with its own curves.
3. The physical side effects of film are added: **halation**, **haze/bloom**, **light leaks**, **vignette** and **grain**.

The tone and colour part (steps 1 and 2) is pure maths in Swift. It is baked into a 3-D colour lookup table (a "cube") that Core Image applies on the GPU. The physical effects are Core Image filter graphs. Everything is deterministic: the same photo, look and seed always produce identical pixels.

---

## 2. Files at a glance

| File | Role |
|---|---|
| `frmr/Features/Camera/FilmModel.swift` | **The film maths**, pure Swift with no Core Image: the colour model, film chain and cube types listed in §4, plus the grain and light-leak helpers (`SeededRandom`, `GrainProfile`, `FilmGrain`, `LightLeak`). |
| `frmr/Features/Camera/ImageProcessor.swift` | **The Core Image pipeline.** `applyStripLook` (strip slots), `renderFullLook` (full-frame look for review, display and Download), the shared private `filmLook(...)` chain, and the effect stages (`applyHalation`, `applyFilmCube`, `applyVignette`, `applyBloom`, `applyLightLeak`, `addGrain`). Also RAW development (`process(rawData:)`) and HEIC encoding. |
| `frmr/Models/FilmLook.swift` | **What the user chose:** stock, `printStock` (nil means the stock's default), `blackAndWhite`, `Strengths` (halation, haze, lightLeak, grain, vignette; 0…1.5, where 1 equals the v4 strength) and `exposure` (EV, −2…+2 in ⅓ stops, v5.2). Codable, with migration from older shapes (a look without `exposure` decodes as 0). |
| `frmr/Features/Camera/FilmSwatch.swift` | v5.2: 2–3 representative colours per stock (fixed skin, sky and foliage patches through the stock's own `FilmChain`), cached. For the dial and editor chips. |
| `frmr/Features/PhotoEdit/FilmPreviewThumbnails.swift` | v5.2: small renders of one photo in every stock / on every print (`PhotoEditViewModel.stockPreviews`, `printPreviews`). |
| `frmr/Models/StripCustomization.swift` | `FilmStock` (the six stocks plus Off) and `PrintStock`, and each stock's links into Constants (`negative`, `defaultPrint`, `availablePrints`, `halationStrength`, `grainIntensity`, `grainSizePixels`, `grainProfile`). Also the strip-level customization: As shot or override, background, strengths. |
| `frmr/Shared/Constants.swift` → `Constants.ImageProcessing.Film` | **Every number.** Curves per stock (`Negative`), prints (`Print`), tone targets, toe, grain, halation, bloom, leak, strengths, seeds and cube settings. Tuning happens here. |
| `frmr/Features/Camera/FilmPreviewRenderer.swift` | **Live viewfinder:** applies only the cube, through the same `FilmLUT.cachedCube`, to camera frames on Metal. No grain or effects. |
| `frmr/Features/Camera/FilmLookRenderScheduler.swift` | Shared JPEG→RAW watcher and debounced, last-wins renderer, used by the diary review and the Photo editor. |
| `frmr/Features/Diary/FilmLookCache.swift` | In-memory cache of rendered display images (entries, Roll thumbnails). |
| `frmr/Features/Strip/StripGenerator.swift` | Lays out strips. Resolves "As shot" per frame and derives each frame's seed. |

**Callers of the pipeline:** `StripGenerator`, `FilmLookCache`, `FilmLookRenderScheduler`, `DiaryReviewViewModel`, `PhotoEditViewModel`, `RollViewModel` (export) and `FilmPreviewRenderer` (cube only).

---

## 3. The pipeline, step by step

```
Capture (RAW + JPEG)
  └─ ImageProcessor.process(rawData:)      RAW development (unchanged since v1/v2 look),
                                           pixels kept in sensor space + orientation tag
      │
      ▼  the ORIGINAL is what gets stored (diary entry, Roll photo) — never a filmed copy
      │
Render time (strip slot, review, thumbnail, Download)
  1. uprightCIImage / sensor-space input   resolve or carry the orientation tag
  2. resize                                strip: aspect-fill + crop to the 4:5 slot (resizedToSlot)
                                           full look: shrink to cover the display size, or keep full res
  3. Exposure      × 2^EV  (v5.2)          stock Off: a plain linear gain here (and nothing else but B&W)
                                           with a stock: the gain rides into steps 4 and 5 (below)
  3b. B&W luminance (if mono)              negative.monoWeights (spectral sensitivity)
  4. Halation      × strengths.halation    highlights (read AFTER the exposure gain) → blur → red-orange tint
                                           → added in LINEAR light
  5. Film cube     (gain baked in)         colour matrix → ×2^EV → negative curve → print curve
                                           → shadow toe + black/white normalisation  (FilmModel)
  6. Vignette      × strengths.vignette    on the printed picture
  7. Haze (bloom)  × strengths.haze        blurred copy, screen-blended
  8. Light leak    × strengths.lightLeak   seeded warm glows outside a frame edge, screen-blended
  9. Grain         × strengths.grain       two seeded octaves, amplitude from print density, last
```

The order is part of the spec and is deliberate:
- Halation goes **before** the cube, so the glow passes through the film's shoulder the way real light does.
- Grain goes **last**, so it sits on top of the print.

**Exposure (v5.2 F-EXP):** the gain is 2^EV on linear light, applied **ahead of the negative curve** so over-exposure rolls off through the film's shoulder and under-exposure lifts through the toe, like exposing film differently, not a brightness slider. Mechanically:
- The gain lives **inside the cube** (`FilmChain.exposureGain`; the cube cache key includes it, so each ⅓-stop step has its own cached cube, `lutCacheLimit` 16). The cube is still indexed by the *unexposed* picture, so nothing clips at the lattice edge. The white and black points stay solved at 0 EV, as with a real print made for a normal exposure.
- Halation reads the exposed light: its key uses `input × gain` and the glow is divided by the gain (the cube multiplies it back), so the glow is what it would be on exposed light.
- Grain follows from the print density, as before.
- With **stock Off** the gain is a plain linear gain (`applyLinearGain`) and hard-clips like any gain; B&W-only (`CIPhotoEffectMono`) follows it.
- **0 EV changes nothing:** gain 1 skips the stage, uses the same cube key, and `FilmLook.altersPhoto` stays false for Off + 0 EV. `exposure` ≠ 0 makes a look "altered" even with stock Off.

**Strength 0 skips the stage entirely**, which is why "0" is pixel-identical to "off". Tests enforce this.

**Stock Off:** steps 3b–9 are skipped (step 3, the plain exposure gain, still runs). Off with B&W uses `CIPhotoEffectMono`, the original v1 look. `applyStripLook` and `renderFullLook` return the input image unchanged when the look alters nothing.

---

## 4. The tone and colour model (`FilmModel.swift`)

**Units:**
- x = log₁₀(E), where E is relative linear exposure and 0.18 is mid grey.
- Densities are optical densities, and transmittance = 10^−D.

**Input:** strip and review photos are already developed (display-referred). We treat linear sRGB as relative scene exposure. This approximation was accepted in v4 (spec F2).

### 4.1 Characteristic curve: `FilmCurve`
Each dye layer has a logistic curve:

```
D(x) = dMin + (dMax − dMin) / (1 + exp(−k·(x − x0)))      k = 4·gamma / (dMax − dMin)
```

- `gamma` is the slope at `x0` (contrast).
- `x0` is the layer's speed point. Moving one layer's `x0` against the others creates a **crossover**, which gives a colour cast that changes with tone.
- `dMin` and `dMax` are the density limits.

The logistic gives a toe and a shoulder and always increases.

### 4.2 Colour separation: `ColourMatrix`
A 3×3 matrix applied to linear light **before** the curves. Each row sums to 1, so neutrals, mid grey and black are unaffected. Helpers:
- `.saturation(a)`: scales colour distance from Rec. 709 luminance.
- `.blueIntoGreen(a)`: blues lean teal.
- `.redBlueCrosstalk(a)`: a slight magenta lean.
- Compose them with `after(_:)`.

Use it for saturation and hue leanings that curves can't produce.

### 4.3 Negative → print: `FilmModel.printed`

```
negative density  Dn = negativeCurve(log10(E · exposureScale))
print sees        xp = offset − Dn             (more negative density = less light)
print density     Dp = printCurve(xp)
output (linear)   10^(−Dp)
```

**Print offsets are solved, not tuned.** `balancedPrintOffset(s)` uses bisection to make mid grey land on `printMidGreyTarget` per channel. A print therefore never adds its own cast; character comes from the stock's curves.

### 4.4 Output normalisation: `OutputNormalisation`
One affine map in linear light, shared by all three channels:
- input white → `printWhiteTarget` (0.96 sRGB);
- input black → the print's `blackTarget` (Lab 6, Cinema 4, Projection 3, Matte 28 /255).

**Why it exists:** without it, whites printed at about 223/255 and blacks at about 20/255 (v4 finding).

### 4.5 Shadow toe: `ShadowToe`
Below the mid-grey pivot (0.18 linear), each channel's response is replaced by a smooth curve. It starts at that channel's black and meets the film curve at the pivot, with the same value and slope, so there is no kink. The steep part sits just under mid grey (`shadowToeExponent` 8), so deep shadows keep the separation of the untouched photo.

**Why:** real low-key photos (IMG_3530 in the calibration set) turned into flat grey. Changing x0 or gamma would also have changed midtones and highlights. **Nothing at or above mid grey is affected.**

### 4.6 One render: `FilmChain`
`FilmChain(negative:print:monochrome:)` pre-computes the offsets, the normalisation and the three toes. `render(r:g:b:)` then does one of two things:
- **Colour:** colour matrix, then each channel through its own toe, or through its own curve pair and the normalisation.
- **Monochrome:** spectral luminance, then the **red** curve pair for all three channels. This applies to a B&W stock, or a colour stock with B&W on.

### 4.7 The cube: `FilmLUT`
- `FilmLUT.cube(...)` evaluates `FilmChain` at every point of a 64³ lattice (`lutDimension`). The lattice is indexed in gamma-encoded sRGB, and the result is Float32 RGBA data for `CIColorCubeWithColorSpace`.
- `cachedCube` keeps up to `lutCacheLimit` (8) cubes, first-in first-out. The cache key is the profiles themselves, not the enum names, so editing a constant can't serve a stale cube.
- **The strip, the full look and the live viewfinder all use the same cube.** What you see in the viewfinder is the same colour and tone as the saved photo.

---

## 5. The physical effects (`ImageProcessor.swift`)

All sizes are **fractions of the output width**, so a slot, a thumbnail and a 12 MP Download look alike. The exception is grain, which is in pixels and rescaled; see below.

| Effect | How | Key constants |
|---|---|---|
| **Halation** | Highlight key max(0, L−t)/(1−t), Gaussian blur, red-orange tint × stock strength × slider, added with `linearDodgeBlendMode` in linear light before the cube. `CIAdditionCompositing` was avoided because premultiply turned the alpha-0 glow black. | `halationThreshold` 0.75, `halationRadiusFraction` 0.012, `halationTint`, `HalationStrength.*` (Cine 500T strongest) |
| **Vignette** (v5) | Radial darkening on the printed picture. Default 0. | `Strength.vignette*` (darkening 0.45, radii 0.45–1.0 of the half-diagonal; untuned) |
| **Haze** (formerly bloom) | Gaussian-blurred copy, screen-blended. | `bloomRadiusFraction` 0.03, `bloomStrength` 0.25 |
| **Light leak** | One or two radial gradients in warm colours, centred just outside a seeded frame edge, screen-blended. Only ever brightens. | `lightLeakColors`, `lightLeakStrength` 0.55, `lightLeak*Fraction/Range` |
| **Grain** | Two octaves of seeded `CIRandomGenerator` noise (fine and coarse, sized by ISO). Colour stocks are mixed toward mono by `grainChroma`; mono stocks use one channel. Amplitude comes from print density through `grainDensityCurve` (via a `CIColorCurves` table). The blend is multiplicative and preserves the mean, so grain never brightens or darkens the photo. | `grainIntensityByISO`, `grainSizePixels`, `Grain.standard` / `Grain.mono3200` (`GrainProfile`), `grainReferenceWidth` 1080 |

**Grain scaling:** `renderFullLook` multiplies grain size by width ÷ `grainReferenceWidth`. Without that, a 12 MP Download would have finer grain than the review screen showed. Strips pass a scale of 1; their grain is tuned at slot size.

---

## 6. Stocks, prints and where each number lives

| Stock (`FilmStock`) | Inspired by (research only) | Default print | Character controls |
|---|---|---|---|
| Daylight 200 | Consumer 200 colour negative | Lab | warm crossover, saturation 1.12, `blueIntoGreen` 0.06 |
| Portrait 400 | Portrait 400 negative | Lab | low gamma, saturation 0.85, `blueIntoGreen` 0.05 (keeps skies cyan, not lavender) |
| Cine 500T | Tungsten cinema negative | Cinema | teal/cyan shadow crossover, strongest halation |
| Slide 100 | Reversal / slide | Projection | saturation 1.35, `redBlueCrosstalk` 0.04, deepest black |
| Mono 400 | Classic 400 B&W | Lab | gamma 0.68 |
| Mono 3200 | High-speed B&W | Lab | `Grain.mono3200`: finer structure, less grain in highlights |

- **Curves and colour matrices:** `Constants.ImageProcessing.Film.Negative.<stock>`
- **Prints:** `Constants.ImageProcessing.Film.Print.<print>`. Lab, Cinema and Matte are for negatives; Projection is for slide only.
- **Brand names:** never in app code or UI strings. The film families named above appear only in `research/v4-film-reference-calibration.md`.

---

## 7. Determinism and seeds

Random elements (grain, light leak) use `SeededRandom` (SplitMix64). Swift's `Hasher` must not be used, because it is randomised per process. Each element gets its own salted stream via `SeededRandom.derive(seed, salt:)`, so toggling one effect never reshuffles another.

| Where | Seed source |
|---|---|
| Strip frame | `StripGenerator.seed(for: date, slot: frameIndex)`; the frame index is global across a multi-strip render |
| Review, editor, Download, entry or Roll display | `StripGenerator.photoLookSeed(for: captureDate)`, so the saved entry shows the grain the user reviewed |
| Booth paper texture | Strip date + strip index (`paperSeedSalt`) |

**Rule:** re-rendering anything with the same inputs must be **byte-identical**. QA's `StripLookRegressionTests` and `FilmAtCaptureRegressionTests` check this.

---

## 8. Invariants: never break these

1. **Orientation:** never call `CIImage(image:)` on a photo. Use `uprightCIImage(from:)`, or work in sensor space and keep the orientation tag (`renderFullLook`). See `.claude/skills/ios-camera-orientation/SKILL.md`.
2. **Neutrality:** the balanced mid grey stays neutral for every stock × print × B&W combination. Colour matrix rows sum to 1.
3. **Monotonicity:** every channel of the chain increases with exposure. The cube must not fold.
4. **Black and white targets:** input 0 → the print's `blackTarget` (±1/255); input 1 → `printWhiteTarget`.
5. **Strength semantics:** 0 equals off (pixel-identical); 1 equals the v4 look; the maximum is 1.5 (`Strength.sliderMaximum`).
6. **Non-destructive:** stored photos are originals. The look is data (`FilmLook`) and is applied at display or export time.
7. **Determinism:** see §7.
8. **Offline, Apple frameworks only:** no third-party code, no network, no AI.
9. **Every number in `Constants`**, with `// OPEN: v4-5` (calibration) or the relevant open decision marked.

---

## 9. How to make common changes

**Tune a stock's colour or contrast:**
1. Edit `Constants.ImageProcessing.Film.Negative.<stock>`. Typical edits:
   - `gamma`: contrast;
   - per-layer `x0`: crossover or cast;
   - the `colour:` matrix: saturation and hue lean;
   - `dMax`: depth.
2. Keep matrix rows summing to 1.
3. Run `FilmModelTests` and `FilmCalibrationTests`. These check warmth order, Portrait being softer than Daylight, Cine's teal shadows, Slide being the most saturated, and Portrait's skies not drifting purple.
4. Regenerate the real-photo sheets (§10) and look at them.

**Change the exposure range or step:** `Constants.ImageProcessing.Film.Exposure` (`range`, `step`). The editor, the snapping (`FilmLook.snappedExposure`) and the tests all read it. A new step size changes how many cubes one stock can need, so check `lutCacheLimit`.

**Change how a print looks** (blacks, contrast): edit `Print.<print>` (`blackTarget`, curves). Offsets re-solve automatically. Run `inputBlackPrintsAtEachPrintsBlackTarget` and the neutral and monotonic tests.

**Add a stock:**
1. Add a `FilmStock` case: label, `shortCode`, `iso`, `negative`, `defaultPrint`, `availablePrints`, `halationStrength`, grain profile.
2. Add its `Negative` and `HalationStrength` constants.
3. Extend `FilmCalibrationTests` with what makes it distinct.
4. The pickers list `FilmStock.allCases` automatically. Check the camera dial and chip short codes fit.

**Add an effect:**
1. Add a `FilmLook.Effect` case with its default strength, and a field in `Strengths`, including Codable migration.
2. Add a stage in `ImageProcessor.filmLook(...)` at the right point in the order, skipped at strength 0.
3. Add the constants and a seed salt if it's random.
4. Add tests: strength 0 equals identity, determinism, and visible change at 1.
5. Update §3 and §5 of this doc.

**Make an effect stronger or weaker for everyone:** change its base constant (e.g. `bloomStrength`), not the slider range. Changing a base value changes how existing photos look, so note it in `CHANGELOG.md`.

**Speed:**
- The cube build is the expensive part; it's cached.
- Strip renders resize first (v4 F1).
- `StripRenderTimingTests` measures a 4 × 12 MP strip; the simulator baseline is about 80 ms warm.

---

## 10. Testing and calibration

| Test file | What it guards |
|---|---|
| `FilmModelTests` | Curve maths, offsets, neutrality, monotonicity, colour-matrix rows sum to 1, cube shape and cache, black/white targets, toe, shadow separation |
| `FilmCalibrationTests` | Per-stock character relationships (F14) |
| `FilmEffectsTests` | Halation, grain, haze, light-leak behaviour, and seed determinism (parameterised) |
| `OffIsIdentityTests` | Strength 0 / stock Off = pixel-identical, for every effect, stock and render surface (parameterised) |
| `FilmLookTests` | `FilmLook` migration, strength 1 = v4, vignette; exposure (v5.2): snapping, Codable and old data, monotonic brightening, shoulder roll-off, plain gain for Off, halation reading exposed light, determinism |
| `FilmCalibrationTests` (also) | Stock swatch colours (v5.2) |
| `ImageProcessorTests` | Orientation mapping (8 cases), slot resize, HEIC tag |
| `StripLookRegressionTests`, `FilmAtCaptureRegressionTests` (QA-owned) | Orientation across every stock × B&W × effect, and determinism |
| `StripRenderTimingTests` | Render time |

The full map of every test file, and the "search before adding a test" rule, are in **`docs/testing.md`**.

**Real-photo calibration (gated):** `FilmStockSampleSheetTests` and `StripSampleRenderTests` are skipped unless environment variables point at a folder of DNGs outside the repo. Personal photos never go in git.

```bash
TEST_RUNNER_FRMR_FILM_SAMPLES_DIR=/path/to/dngs TEST_RUNNER_FRMR_FILM_SAMPLES_OUT=/path/to/out \
xcodebuild -project frmr.xcodeproj -scheme frmr \
  -destination 'platform=iOS Simulator,id=<simulator-id>' \
  -parallel-testing-enabled NO -only-testing:frmrTests/FilmStockSampleSheetTests test
```

The test writes one labelled contact sheet per photo, with all stocks side by side. Always compare sheets before and after a tuning change. The reference research behind the current tuning is in `research/v4-film-reference-calibration.md`.

**Run the whole suite** with `-parallel-testing-enabled NO`; parallel simulator clones fail on this machine.

---

## 11. History (why things are the way they are)

| When | Change | Why |
|---|---|---|
| v4 F0 | `uprightCIImage` | `CIImage(image:)` dropped the orientation tag, so photos came out sideways |
| v4 F1 | Resize first | Filtering full 12 MP for a 260 px slot was about 20× slower |
| v4 F2/F3 | Negative → print chain, solved offsets | Character from curves, without print casts |
| v4 tone follow-up | Output normalisation | Whites at 223/255 looked grey |
| v4 shadow fix | `ShadowToe`, per-print black targets | Real DNGs showed grey blacks and crushed shadows |
| v4 F14 | Colour matrices, grain profiles | Calibrated against real-film reference scans |
| v4 | Grain scaled to the frame in `renderFullLook` | Download must match the review |
| v5 F5 | `FilmLook` strengths, vignette, Haze = bloom | Sliders everywhere; 0 = off |
| v5.2 F-EXP | `FilmLook.exposure`, gain baked into the cube, halation reads exposed light | Edit exposure after the shot, behaving like film (shoulder roll-off), not a brightness slider |

Detailed decisions and open items are in `frmr-v4-spec.md` (Parts 1–2, open decisions v4-1…v4-16) and `frmr-v5-spec.md`.
