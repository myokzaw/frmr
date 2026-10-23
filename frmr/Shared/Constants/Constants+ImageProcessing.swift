import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: CoreImage pipeline — translated from Iphone_Simple.xmp
    // Three values are marked OPEN and need tuning against real captures.
    enum ImageProcessing {
        static let rawNoiseReduction: Float = 0.3
        static let rawNoiseReductionSharpness: Float = 0.2

        // Tone curve — normalised from LR's 0–255 range
        // Shared anchor points (same in Simple and Sunset presets)
        static let toneCurveShadowInput: Float = 0.282
        static let toneCurveShadowOutput: Float = 0.239

        // Simple preset midtone (neutral, everyday default)
        static let toneCurveMidSimpleInput: Float = 0.820
        static let toneCurveMidSimpleOutput: Float = 0.824

        // Sunset preset midtone (slightly lifted, warmer feel)
        static let toneCurveMidSunsetInput: Float = 0.812
        static let toneCurveMidSunsetOutput: Float = 0.843

        static let colorContrast: Float = 1.055
        static let colorSaturation: Float = 1.070
        static let vibrance: Float = 0.07
        static let noiseLevel: Float = 0.02
        static let noiseSharpness: Float = 0.40

        // v5.2 S8: the fixed reference patches (gamma-encoded sRGB) a stock's
        // swatch colours are rendered from: skin, sky, foliage
        enum Swatch {
            static let patches: [(r: Double, g: Double, b: Double)] = [
                (0.82, 0.62, 0.52),
                (0.42, 0.62, 0.86),
                (0.30, 0.52, 0.26),
            ]
        }

        // OPEN: tune these against real RAW captures before shipping (project.md §13 #5)
        static let unsharpRadius: Float = 0.8
        static let unsharpIntensity: Float = 0.3
        static let vignetteIntensity: Float = 0.25
        static let vignetteRadius: Float = 1.6
        static let warmPushKelvin: Float = 5800
        static let warmPushTint: Float = 8

        // MARK: Film model (v4 F2/F3) — lives here so the numbers sit with the
        // rest of the pipeline's. Curve shapes are aesthetic starting points.
        // OPEN: v4-5 — tune every curve against published manufacturer
        // characteristic curves and real captures on device. Never copy another
        // app's stock data.
        // Known trade-off of the v4 approximation (display-referred input treated
        // as scene exposure): shadows below ~20% sRGB compress, and before the
        // output normalisation stage a diffuse white printed at ~220–235/255.
        enum Film {
            // OPEN: v4-5 — sRGB-encoded value input white prints at, after
            // the print stage (OutputNormalisation). Input black prints at
            // each print's own `blackTarget` (Print below).
            static let printWhiteTarget: Double = 0.96
            // OPEN: v4-5 — shadow toe (ShadowToe in FilmModel). Below this
            // linear input (mid grey) each channel's film response is
            // replaced by a monotone curve that keeps shadow separation close
            // to the untouched photo; at and above it nothing changes.
            static let shadowToePivot: Double = 0.18
            // How late the toe's slope climbs to the film's slope at the
            // pivot: higher keeps deep-shadow separation nearer the untouched
            // photo and moves the stock's extra contrast up toward mid grey.
            // 8 keeps every stock on its default print within 25% of Off's
            // separation for input 0.02–0.20.
            static let shadowToeExponent: Double = 8
            // The film's slope at the pivot is measured over pivot/this
            static let shadowToeSlopeSamples = 256
            static let midGrey: Double = 0.18
            static let midGreyLogExposure: Double = log10(midGrey)
            // Scales input before the log so 0.18 lands on each stock's x0
            static let exposureScale: Double = 1.0
            // Floor for log10 so pure black stays finite (−5 is far past every toe)
            static let minimumExposure: Double = 1e-5
            // Neutral 0.18 in comes out neutral 0.18 out (balanced print)
            static let printMidGreyTarget: Double = 0.18
            // Bisection bounds and iterations for the print offset solve.
            // 200 halvings of ±20 is well below Double precision.
            static let printOffsetSearchRange: Double = 20
            static let printOffsetIterations = 200

            // 64³ is exact enough for 8-bit output (spec §F3)
            static let lutDimension = 64
            // 4 MB per cube at 64³; the spec's 48-entry worst case would be
            // ~190 MB, so the cache keeps the most recent few only
            // v5.2: exposure bakes its gain into the cube, so one stock
            // explored across the ⅓-stop steps needs a few cubes
            static let lutCacheLimit = 16
            // OPEN: v4-8 — decision flag: the film chain is a baked colour
            // cube, not a Metal CIColorKernel (no -fcikernel build rules; the
            // tested Swift produces the pixels). Flip only if profiling demands.
            static let usesColourCube = true
            // OPEN: v4-4 — overturned by v5 F5: the strip/photo-time vignette
            // now exists as an effect strength (Strength below). Its default
            // is 0 everywhere, so every existing look renders as before; the
            // RAW development step keeps its own fixed vignette
            // (ImageProcessing.vignette*).

            // MARK: Halation (v4 F4)
            // OPEN: v4-5 — threshold, radius, tint and strengths are aesthetic
            // estimates; calibrate against real captures of point lights.
            // Linear luminance above which light reaches the base and bounces back
            static let halationThreshold: Double = 0.75
            // Glow radius as a fraction of the slot's output width
            static let halationRadiusFraction: Double = 0.012
            // The bounce re-exposes the red-sensitive layer first: red-orange
            static let halationTint = (r: 1.0, g: 0.30, b: 0.08)
            enum HalationStrength {
                static let daylight200: Double = 0.35
                static let portrait400: Double = 0.30
                // No anti-halation backing: by far the strongest
                static let cine500T: Double = 0.90
                static let slide100: Double = 0.20
                static let mono400: Double = 0.30
                static let mono3200: Double = 0.40
            }

            // MARK: Grain v2 (v4 F5) — statistical stand-in for the Boolean
            // grain model (Newson et al. 2017): two noise octaves whose
            // amplitude follows print density.
            // OPEN: v4-5 — intensities, sizes, chroma and the density curve
            // are aesthetic estimates; calibrate against real scans.
            // Relative transmittance fluctuation per speed. 100/400/3200 carry
            // over v2's ISO 100/400/3200 values; others interpolate per stop.
            static let grainIntensityByISO: [Int: Double] = [100: 0.04, 400: 0.12, 3200: 0.30]
            // Fine-octave grain size in output pixels (the strip look runs at slot size)
            static let grainSizePixels: [Int: Double] = [100: 1.0, 400: 1.4, 3200: 2.2]
            // Full-frame looks (review screen, entry display, Download) are
            // rendered at very different widths. Their grain is sized relative
            // to the frame: grainSizePixels holds at this upright width and
            // scales linearly with it, so a 12 MP Download has the same
            // grain-to-frame proportion as the screen-size review render.
            // OPEN: v4-5 — reference = a typical review render width (phone
            // screen, in pixels); the strip slot keeps unscaled grain.
            static let grainReferenceWidth: Double = 1080
            // The coarse octave models clumping: bigger, weaker
            static let grainCoarseSizeMultiplier: Double = 2.5
            static let grainFineWeight: Double = 0.7
            static let grainCoarseWeight: Double = 0.3
            // Colour stocks: 0 = monochrome grain, 1 = fully independent dye layers
            static let grainChroma: Double = 0.35
            // Amplitude weight over normalised print density, evenly spaced
            // from paper white (0) to the densest black (1). A tunable U:
            // grain shows in highlights, hides in midtones, is heaviest in
            // the deep shadows. Replaces v2's grainLuminanceCurve.
            static let grainDensityCurve: [Double] = [0.8, 0.3, 1.0]
            // Per-stock grain structure (v4 F14). Every stock uses the
            // values above except where a profile below says otherwise.
            enum Grain {
                static let standard = GrainProfile(
                    fineWeight: grainFineWeight,
                    coarseWeight: grainCoarseWeight,
                    coarseSizeMultiplier: grainCoarseSizeMultiplier,
                    sizeScale: 1,
                    densityCurve: grainDensityCurve
                )
                // OPEN: v4-5 — pushed 3200 B&W: fine-structured grain that is
                // strong in the mids and backs off in bright, thin areas, so a
                // bright sky reads as grain, not mottling. Less weight on a
                // smaller coarse octave, a slightly finer size, and a density
                // curve that rises from paper white to the mids.
                static let mono3200 = GrainProfile(
                    fineWeight: 0.85,
                    coarseWeight: 0.15,
                    coarseSizeMultiplier: 1.8,
                    sizeScale: 0.8,
                    densityCurve: [0.25, 0.9, 1.0]
                )
            }
            // Print density that maps to 1 on the curve's axis
            static let grainDensityRange: Double = 2.0
            static let grainAmplitudeTableSize = 64
            // Noise-tile offsets are drawn from 0..<range pixels per seed
            static let grainSeedOffsetRange: UInt64 = 4096
            // Per-effect salts: each random effect draws its own stream from
            // the slot seed, so toggling one never reshuffles another
            static let grainSeedSalt: UInt64 = 0x6772_6169_6E00_0001
            static let lightLeakSeedSalt: UInt64 = 0x6C65_616B_0000_0002

            // MARK: Bloom and light leak (v4 F6) — both off by default
            // OPEN: v4-5 — radii, strengths and colours are aesthetic estimates
            // Mist-filter glow radius as a fraction of the slot's output width
            static let bloomRadiusFraction: Double = 0.03
            // Screen-blend amount of the blurred copy
            static let bloomStrength: Double = 0.25
            // Linear-light glow colours, outermost first: amber, then red.
            // OPEN: v4-3 — fixed per strip (seed from date and slot)
            static let lightLeakColors: [(r: Double, g: Double, b: Double)] = [
                (r: 1.0, g: 0.45, b: 0.10),
                (r: 0.95, g: 0.12, b: 0.05),
            ]
            static let lightLeakStrength: Double = 0.55
            // First glow's radius, as a fraction of the slot's longer side
            static let lightLeakRadiusFraction: Double = 0.75
            // Each further glow is this much smaller and this far along the edge
            static let lightLeakSpotFalloff: Double = 0.55
            static let lightLeakSpotSpacing: Double = 0.12
            // Centre sits this far outside the frame (fraction of the longer side)
            static let lightLeakOutsideFraction: Double = 0.12
            // Where along the chosen edge the leak may centre
            static let lightLeakAlongRange: ClosedRange<Double> = 0.15...0.85

            // Orthochromatic-to-panchromatic sensitivity, applied to linear
            // light. Each set sums to 1 so a neutral grey keeps its value.
            enum Spectral {
                // Rec. 709 luminance: a modern panchromatic emulsion
                static let panchromatic = SpectralWeights(r: 0.2126, g: 0.7152, b: 0.0722)
                // Extended red sensitivity, typical of fast pushed emulsions:
                // skies darken less, skin lightens
                static let extendedRed = SpectralWeights(r: 0.30, g: 0.60, b: 0.10)
            }
            // OPEN: v4-7 — a colour stock with B&W on renders through its own
            // red curve pair with these weights
            static let colourStockMonoWeights = Spectral.panchromatic

            /// Builds a curve whose speed point sits `speedOffset` log units
            /// from mid grey. Shifting one layer against the others is the
            /// stock's crossover.
            static func curve(dMin: Double, range: Double, gamma: Double, speedOffset: Double = 0) -> FilmCurve {
                FilmCurve(dMin: dMin, dMax: dMin + range, gamma: gamma, x0: midGreyLogExposure + speedOffset)
            }

            static func printCurve(dMin: Double, dMax: Double, gamma: Double) -> FilmCurve {
                // A print's x0 is arbitrary: the balanced offset positions it
                FilmCurve(dMin: dMin, dMax: dMax, gamma: gamma, x0: 0)
            }

            // OPEN: v4-6 — stored v2 raw values → v4 stock raw values (spec §F7).
            // Anything not listed migrates to Off.
            static let legacyStockMapping: [String: String] = [
                "iso100": "daylight200",
                "iso400": "portrait400",
                "iso3200": "cine500T",
            ]
            // The pre-v2 grain toggle's "on" was v2's ISO 400
            static let legacyGrainEnabledStock = "iso400"

            // OPEN: v4-2 — overturned by v5 F5: effects are 0…1 strengths
            // (Strength below); a v4 "on" migrates to Strength.migratedOn
            static let effectsAreToggles = false
            // Halation defaults on for every stock, at the stock's own strength
            static let halationOnByDefault = true

            // MARK: Exposure (v5.2 F-EXP)
            enum Exposure {
                /// EV range of the editor's Exposure tool, in ⅓-stop steps
                static let range: ClosedRange<Double> = -2...2
                static let step: Double = 1.0 / 3.0
            }

            // MARK: Effect strengths (v5 F5)
            // One scale for every effect: 1 is exactly the v4 strength, 0 is
            // pixel-identical to the effect being off.
            enum Strength {
                // OPEN: v5-6 — slider maximum relative to the v4 strength
                static let sliderMaximum: Double = 1.5
                // A v4 toggle that was on keeps its v4 strength
                static let migratedOn: Double = 1
                // What a stock starts with: halation on (as v4), grain at the
                // stock's own intensity, the rest opt-in
                static let defaultHalation: Double = 1
                static let defaultHaze: Double = 0
                static let defaultLightLeak: Double = 0
                static let defaultGrain: Double = 1
                static let defaultVignette: Double = 0
                // Vignette at strength 1: how dark the frame corners get
                // (multiplicative, in the print's output space) and where the
                // falloff starts and ends, as fractions of the half-diagonal.
                // Aesthetic estimates, tuned by eye.
                static let vignetteDarkening: Double = 0.45
                static let vignetteInnerRadiusFraction: Double = 0.45
                static let vignetteOuterRadiusFraction: Double = 1.0
            }

            // MARK: Negatives
            // OPEN: v4-5 — v4 F14 calibration against real-film references
            // (research/v4-film-reference-calibration.md §1). Directional,
            // judged on the user's sample sheets; not measured data.
            enum Negative {
                // Consumer 200 colour negative: punchy, warm yellow-orange mids
                // and highlights (red steepest and fastest, blue slowest), a
                // little extra saturation, and blues leaning teal
                static let daylight200 = NegativeProfile(
                    r: curve(dMin: 0.15, range: 5.0, gamma: 0.64, speedOffset: 0.04),
                    g: curve(dMin: 0.15, range: 5.0, gamma: 0.58),
                    b: curve(dMin: 0.15, range: 5.0, gamma: 0.50, speedOffset: -0.03),
                    isMonochrome: false,
                    monoWeights: colourStockMonoWeights,
                    colour: ColourMatrix.blueIntoGreen(0.06).after(.saturation(1.12))
                )
                // Portrait 400 negative: clearly softer than Daylight — lower
                // gamma, restrained saturation, a slight warm skin bias. A
                // little blue into green keeps desaturated skies pastel cyan
                // rather than lavender (user review of the sample sheets)
                static let portrait400 = NegativeProfile(
                    r: curve(dMin: 0.15, range: 4.2, gamma: 0.43, speedOffset: 0.02),
                    g: curve(dMin: 0.15, range: 4.2, gamma: 0.42),
                    b: curve(dMin: 0.15, range: 4.2, gamma: 0.41, speedOffset: -0.01),
                    isMonochrome: false,
                    monoWeights: colourStockMonoWeights,
                    colour: ColourMatrix.blueIntoGreen(0.05).after(.saturation(0.85))
                )
                // Tungsten motion-picture negative in daylight: the red layer is
                // the steep one, so shadows lose red and go teal/cyan while
                // highlights stay a touch warm; saturated reds
                static let cine500T = NegativeProfile(
                    r: curve(dMin: 0.12, range: 5.0, gamma: 0.53, speedOffset: -0.02),
                    g: curve(dMin: 0.12, range: 5.0, gamma: 0.56),
                    b: curve(dMin: 0.12, range: 5.0, gamma: 0.57, speedOffset: 0.02),
                    isMonochrome: false,
                    monoWeights: colourStockMonoWeights,
                    colour: .saturation(1.1)
                )
                // Reversal: all the contrast lives here (its print is
                // `projection`); the most saturated stock, with red and blue a
                // touch steeper than green for a slight warm-magenta bias
                static let slide100 = NegativeProfile(
                    r: curve(dMin: 0.1, range: 6.0, gamma: 1.76, speedOffset: 0.02),
                    g: curve(dMin: 0.1, range: 6.0, gamma: 1.72),
                    b: curve(dMin: 0.1, range: 6.0, gamma: 1.76),
                    isMonochrome: false,
                    monoWeights: colourStockMonoWeights,
                    colour: ColourMatrix.redBlueCrosstalk(0.04).after(.saturation(1.35))
                )
                // Classic 400 B&W: a little gritty midtone contrast
                static let mono400 = NegativeProfile(
                    r: curve(dMin: 0.10, range: 4.0, gamma: 0.68),
                    g: curve(dMin: 0.10, range: 4.0, gamma: 0.68),
                    b: curve(dMin: 0.10, range: 4.0, gamma: 0.68),
                    isMonochrome: true,
                    monoWeights: Spectral.panchromatic
                )
                // Pushed: steep, so shadows block up and highlights snap
                static let mono3200 = NegativeProfile(
                    r: curve(dMin: 0.15, range: 5.0, gamma: 0.88),
                    g: curve(dMin: 0.15, range: 5.0, gamma: 0.88),
                    b: curve(dMin: 0.15, range: 5.0, gamma: 0.88),
                    isMonochrome: true,
                    monoWeights: Spectral.extendedRed
                )
            }

            // MARK: Prints
            enum Print {
                // Neutral, moderate contrast
                // OPEN: v4-5 — black targets (sRGB/255): lab 6, cinema 4,
                // projection 3, matte a deliberate 28
                static let lab = PrintProfile(
                    r: printCurve(dMin: 0.0, dMax: 2.15, gamma: 2.8),
                    g: printCurve(dMin: 0.0, dMax: 2.15, gamma: 2.8),
                    b: printCurve(dMin: 0.0, dMax: 2.15, gamma: 2.8),
                    blackTarget: 6.0 / 255
                )
                // Contrasty; green and blue share a lower Dmax, so the blacks
                // lean teal/cyan rather than blue (v4 F14)
                static let cinema = PrintProfile(
                    r: printCurve(dMin: 0.0, dMax: 2.30, gamma: 3.2),
                    g: printCurve(dMin: 0.0, dMax: 2.15, gamma: 3.1),
                    b: printCurve(dMin: 0.0, dMax: 2.15, gamma: 3.1),
                    blackTarget: 4.0 / 255
                )
                // Low Dmax lifts the blacks; a denser blue base tints paper white warm
                static let matte = PrintProfile(
                    r: printCurve(dMin: 0.0, dMax: 1.75, gamma: 2.6),
                    g: printCurve(dMin: 0.01, dMax: 1.75, gamma: 2.6),
                    b: printCurve(dMin: 0.04, dMax: 1.75, gamma: 2.6),
                    blackTarget: 28.0 / 255
                )
                // Slide film is viewed directly: a gentle, wide curve that
                // stands in for identity so the slide's own contrast shows
                static let projection = PrintProfile(
                    r: printCurve(dMin: 0.0, dMax: 2.4, gamma: 1.3),
                    g: printCurve(dMin: 0.0, dMax: 2.4, gamma: 1.3),
                    b: printCurve(dMin: 0.0, dMax: 2.4, gamma: 1.3),
                    blackTarget: 3.0 / 255
                )
            }
        }
    }
}
