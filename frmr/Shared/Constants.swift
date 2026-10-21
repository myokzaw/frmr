import Foundation
import CoreGraphics

// nonisolated: pure immutable values, safely readable from any thread
// (the camera pipeline reads these off the main actor)
nonisolated enum Constants {

    // MARK: Diary
    static let promptSoftLimit = 120        // characters typed before the count indicator appears
    // OPEN: maximum entry character count TBD (project.md §13 #1) — 280 is the conservative default
    static let entryCharacterLimit = 280
    static let entriesPerStrip = 4

    // MARK: Diary interaction (v2 F8b)
    enum Diary {
        // Fast enough not to feel slow, slow enough to register as deliberate
        static let promptTypewriterInterval: TimeInterval = 0.03

        // v4 F10 diary review. Stock chips can be tapped quickly; waiting
        // this long after the last tap renders once instead of per tap.
        static let reviewRenderDebounce: TimeInterval = 0.15
        // v4 F10: a diary capture opens DiaryReviewView before the prompt
        // screen. false would go straight to the prompt with the camera's
        // stock, as before F10. (Flipped by frontend with lead approval.)
        static let presentsReviewStep = true

        // v4 F13 Download: how long the "Saved" state shows
        static let downloadSavedConfirmationDuration: TimeInterval = 1.5
        // HEIC quality for the saved film-look photo; matches the JPEG
        // capture quality so a download is no worse than the original
        static let downloadHEICQuality: Double = 0.85
        // OPEN: v4-15 — block a second Download of the same photo and stock?
        // Default: allow it; each tap saves one photo.
        static let blocksRepeatDownload = false
        // OPEN: v4-13 — an entry's stock is fixed once saved (not editable
        // in v4); DiaryEntry exposes it read-only
        static let entryStockIsEditable = false

        // v4 F11 display cache. OPEN: v4-11 — rendered copies are kept in
        // memory only (never written to disk); this caps that memory.
        static let displayCacheCostLimitBytes = 96 * 1024 * 1024
    }

    // MARK: Camera
    static let jpegCompressionQuality: Float = 0.85
    // OPEN: WB persistence TBD — the setting exists but capture always resets
    // to Auto on launch until the decision lands (build notes)
    static let rememberWhiteBalanceDefault = false

    // MARK: Camera controls (v2 F1–F3, F6)
    enum Camera {
        // Delay before the single retry of a failed portrait-lock request
        static let orientationLockRetryDelay: TimeInterval = 0.3

        // Tap-to-focus indicator (F1)
        static let focusIndicatorSize: CGFloat = 72
        static let focusIndicatorStroke: CGFloat = 1.5
        static let focusIndicatorAppearScale: CGFloat = 1.2
        static let focusIndicatorAppearDuration: TimeInterval = 0.15
        static let focusIndicatorHoldDuration: TimeInterval = 0.5
        static let focusIndicatorFadeDuration: TimeInterval = 0.4
        // Total on-screen life of the indicator, after which the view model clears it
        static let focusIndicatorDuration: TimeInterval = 1.2
        // OPEN: v2-1 — lock focus once it settles, or stay in continuous auto?
        // Default is continuous (less jarring if the subject moves), so this
        // timeout is currently only the window the KVO observer stays attached.
        static let focusSettleDuration: TimeInterval = 2.0
        static let lockFocusAfterTap = false

        // Exposure compensation (F2)
        static let exposureBiasMin: Float = -2.0
        static let exposureBiasMax: Float = 2.0
        static let exposureDragScale: CGFloat = 80    // points of drag per 1 EV
        static let exposureIndicatorFadeDelay: TimeInterval = 1.0
        static let exposureIndicatorFontSize: CGFloat = 12
        static let exposureIndicatorSpacing: CGFloat = 4
        static let exposureIndicatorPadding: CGFloat = 12
        // OPEN: v2-2 — persist EV bias across launches? Default: no.
        // (v5-4 confirms: WB and EV reset on launch.)
        static let persistExposureBias = false
        // v5 F3: the EV chip's slider moves in third-stop detents
        static let exposureStepsPerStop = 3
        static let exposureStep: Float = 1 / Float(exposureStepsPerStop)

        // v5 F3 white balance fine-tune (Kelvin and tint sliders)
        static let whiteBalanceKelvinRange: ClosedRange<Float> = 2500...9000
        static let whiteBalanceTintRange: ClosedRange<Float> = -50...50
        // The Kelvin a manual white balance starts from when the first
        // slider is touched while on Auto
        static let whiteBalanceManualStartKelvin: Float = 5600
        static let whiteBalanceManualStartTint: Float = 0
        // OPEN: v5-4 — WB and EV reset on launch (not persisted)
        static let persistWhiteBalanceAndExposure = false
        // OPEN: v5-9 — the app always launches in Photo mode; the stored
        // capture mode (DefaultsKeys.captureMode) no longer decides it
        static let launchModeFollowsStoredCaptureMode = false

        // Pinch-to-zoom (F3)
        static let zoomRampRate: Float = 4.0
        static let minZoomFactor: CGFloat = 1.0
        // Soft cap: devices go higher but quality degrades past this
        static let maxZoomFactor: CGFloat = 10.0

        // Animated preview grain (F6)
        // OPEN: v2-3 — benchmark on A15; disable if the viewfinder drops below 24fps
        static let animatedGrainEnabled = true
        static let grainRefreshInterval: TimeInterval = 0.083   // ~12fps
        static let liveGrainOpacity: CGFloat = 0.08
        static let liveGrainTileSize: CGFloat = 180             // noise tile is tiled to fill

        // Orientation: interface stays locked to portrait so the preview never
        // rotates (would shift crop/composition under the user); chrome
        // counter-rotates in place instead so it still reads upright.
        static let orientationRotationDuration: TimeInterval = 0.3

        // v4 F9 live film preview. The data output's connection is set to the
        // portrait angle once (never re-angled to the horizon, see
        // ios-camera-orientation); 90° is portrait for both cameras' sensors.
        static let portraitPreviewRotationAngle: CGFloat = 90
        // OPEN: v4-14 — 30 fps is the A15 target; measure on device
        static let filmPreviewFramesPerSecond = 30
        // OPEN: v4-10 — the camera's stock is its own default, not the strip's
        static let filmStockSharesStripDefault = false
        // OPEN: v4-12 — a gallery-picked photobooth photo takes the camera's
        // current stock (false would add it as Off)
        static let galleryPicksUseCameraStock = true
    }

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
            static let lutCacheLimit = 8
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

    // MARK: White balance presets (temperature K, tint)
    enum WhiteBalance {
        static let sunlight: (Float, Float) = (5500, 10)
        static let cloudy: (Float, Float) = (6500, 15)
        static let fluorescent: (Float, Float) = (4000, -20)
        static let shade: (Float, Float) = (7500, 20)
        static let tungsten: (Float, Float) = (3200, 0)
        static let manualMin: Float = 2500
        static let manualMax: Float = 8000
    }

    // MARK: Strip layout (project.md §10, logical points; rendered at renderScale)
    enum Strip {
        // v4 F15 booth strip. OPEN: v4-16 — proportions are tuned by eye
        // against real booth strips: thin even border, frames nearly
        // touching, a slim caption band under each frame.
        // Width ÷ height of a frame: 4:5 portrait, like a booth print
        static let cellAspectRatio: CGFloat = 0.8
        static let width: CGFloat = 150
        // Paper around the frames on all four sides
        static let border: CGFloat = 6
        // Paper between one frame's caption band and the next frame (and
        // between the last caption band and the date stamp)
        static let frameGap: CGFloat = 4
        // Lines in each frame's caption band on the rendered strip: one keeps
        // the band slim so frames stay nearly touching; longer captions
        // truncate with an ellipsis (the full text stays in the diary)
        static let boothCaptionLines = 1
        // Booth prints have slightly soft frame corners
        static let frameCornerRadius: CGFloat = 2.5
        // OPEN: v4-9 — separate white paper border on a black strip. Default
        // none: true would paint the border white around the background.
        static let drawsPaperBorder = false
        static let captionSpacing: CGFloat = 2   // gap between a photo and its caption
        static let captionFontSize: CGFloat = 9
        static let captionMaxLines = 2
        static let dateFontSize: CGFloat = 8
        static let dateLetterSpacing: CGFloat = 0.12
        static let renderScale: CGFloat = 2
        static let emptySlotAlpha: CGFloat = 0.08
        // Odd 64-bit multiplier spreading slot indices across the seed space
        // before mixing (v4 F4–F6 per-slot seeds)
        static let slotSeedStride: UInt64 = 0x9E37_79B9_7F4A_7C15

        // v4 F15 paper: warm off-white and near-black photographic paper
        // (sRGB 0–1), never pure #FFFFFF or #000000
        static let paperWhite: (r: Double, g: Double, b: Double) = (0.957, 0.941, 0.906)
        static let paperBlack: (r: Double, g: Double, b: Double) = (0.090, 0.086, 0.082)
        // Faint paper texture: ± this much sRGB per texture cell, cells of
        // this many output pixels, smoothed by drawing the grid scaled up
        static let paperTextureAmplitude: Double = 0.012
        static let paperTextureCellPixels: CGFloat = 2
        // Separates the paper texture's random stream from the frames' seeds
        static let paperSeedSalt: UInt64 = 0x7061_7065_7200_0001

        // v4 F12: the stored Settings value for "As shot" (no strip-wide
        // stock override). Not a FilmStock raw value, so a v4 build reading it
        // falls back to Off rather than misreading it as a stock.
        static let asShotStoredValue = "asShot"
    }

    // MARK: Camera UI (project.md §2, screens 1 & 3)
    enum CameraUI {
        static let shutterOuterDiameter: CGFloat = 76
        static let shutterInnerDiameter: CGFloat = 64
        static let shutterRingWidth: CGFloat = 4
        static let shutterBottomPadding: CGFloat = 28
        static let chipFontSize: CGFloat = 12
        static let chipHorizontalPadding: CGFloat = 12
        static let chipVerticalPadding: CGFloat = 7
        static let chipSpacing: CGFloat = 8
        static let chipInactiveOpacity: CGFloat = 0.14
        static let modePillFontSize: CGFloat = 13
        static let modePillPadding: CGFloat = 4

        // Rotate-in-place chrome (replaces v3 F2/F4): every chip is a fixed
        // circle, so turning it about its centre never overflows its frame
        static let chipDiameter: CGFloat = 44
        static let chipIconSize: CGFloat = 16

        // v3 F3 — collapsible white balance
        static let wbExpandAnimationDuration: TimeInterval = 0.2

        // v4 F9 — Film chip: glyph over a short stock code inside the 44pt
        // circle; the content width keeps "M3.2K" clear of the edge
        static let filmChipSymbolSize: CGFloat = 10
        static let filmChipCodeFontSize: CGFloat = 10
        static let filmChipCodeMinScale: CGFloat = 0.7
        static let filmChipLineSpacing: CGFloat = 1
        static let filmChipContentWidth: CGFloat = 36

        // v3 F1 — device-side diagnosis switch: renders the live
        // rotation angle over the camera so a device photograph can prove
        // what actually reaches the views (DEBUG builds only)
        static let chromeDebugOverlayEnabled = false
        static let slotSize: CGFloat = 64
        static let slotCornerRadius: CGFloat = 8
        static let slotDashWidth: CGFloat = 1.5
        static let slotDashLength: CGFloat = 4
        static let slotBorderOpacity: CGFloat = 0.3
        static let slotSpacing: CGFloat = 10
        static let secondaryButtonSize: CGFloat = 44
        static let secondaryButtonCornerRadius: CGFloat = 9
        static let generateButtonVerticalPadding: CGFloat = 9
        static let disabledControlOpacity: CGFloat = 0.5
        static let captionFontSize: CGFloat = 11
        static let captionOpacity: CGFloat = 0.45
        static let captionMaxWidth: CGFloat = 300
        static let captionMinScale: CGFloat = 0.7
        static let permissionTextMaxWidth: CGFloat = 280
        static let permissionTextMinScale: CGFloat = 0.8

        // Landscape dock on the far right edge
        static let dockSpacing: CGFloat = 10
        static let dockTrailingPadding: CGFloat = 12

        // v5 F2 stock dial: a snapping strip of fixed-width detents above
        // the shutter; the strip never turns, each code label does
        static let dialItemWidth: CGFloat = 60
        static let dialHeight: CGFloat = 44
        static let dialCodeFontSize: CGFloat = 14
        static let dialUnselectedOpacity: CGFloat = 0.5
        static let dialSelectedScale: CGFloat = 1.15
        static let dialTickWidth: CGFloat = 2
        static let dialTickHeight: CGFloat = 8
        static let dialCaptionSpacing: CGFloat = 4
        static let dialSnapAnimationDuration: TimeInterval = 0.2

        // v5 F3 Photo-mode WB / EV panels (one open at a time)
        static let panelCornerRadius: CGFloat = 18
        static let panelPadding: CGFloat = 12
        static let panelSpacing: CGFloat = 10
        static let panelBackgroundOpacity: CGFloat = 0.55
        static let panelHorizontalMargin: CGFloat = 16
        static let panelMaxWidth: CGFloat = 420
        static let panelSliderLabelWidth: CGFloat = 52
        static let panelValueWidth: CGFloat = 56
        static let kelvinSliderStep: Double = 50
        static let tintSliderStep: Double = 1
        static let panelAnimationDuration: TimeInterval = 0.2

        // v5: last Roll photo beside the shutter
        static let lastPhotoSize: CGFloat = 44
        static let lastPhotoCornerRadius: CGFloat = 10
        static let lastPhotoBorderWidth: CGFloat = 1.5
        static let lastPhotoBorderOpacity: CGFloat = 0.8
    }

    // MARK: Entry editor UI (project.md §2, screen 2)
    enum EditorUI {
        static let photoHeightFraction: CGFloat = 0.38
        static let promptFontSize: CGFloat = 25
        static let entryFontSize: CGFloat = 16
        static let charCountFontSize: CGFloat = 12
        static let cardCornerRadius: CGFloat = 12
        static let buttonCornerRadius: CGFloat = 10
        static let buttonPadding: CGFloat = 16
        static let entryMinHeight: CGFloat = 120
        static let linkFontSize: CGFloat = 14
        static let linkSpacing: CGFloat = 28
    }

    // MARK: Library UI (project.md §2, screen 5)
    enum LibraryUI {
        static let titleFontSize: CGFloat = 30
        static let thumbnailSize: CGFloat = 56
        static let thumbnailCornerRadius: CGFloat = 8
        static let excerptFontSize: CGFloat = 15
        static let sectionFontSize: CGFloat = 12
        static let tabFontSize: CGFloat = 14
        static let rowSpacing: CGFloat = 14
        static let stripThumbnailHeight: CGFloat = 220
    }

    // MARK: Full-screen detail viewers (entry photo / strip)
    enum DetailUI {
        static let closeButtonSize: CGFloat = 32
        static let closeIconSize: CGFloat = 14
        static let textPanelMaxHeight: CGFloat = 260
    }

    // MARK: Photo edit screen UI (v5 F4)
    enum PhotoEditUI {
        static let topBarHeight: CGFloat = 52
        static let topBarSpacing: CGFloat = 8
        static let hintOpacity: CGFloat = 0.6
        static let hintMinScale: CGFloat = 0.7
        static let sectionSpacing: CGFloat = 12
        static let tabHeight: CGFloat = 40
        static let tabUnderlineHeight: CGFloat = 2
        static let toolPanelHeight: CGFloat = 252
        static let actionButtonHeight: CGFloat = 50
        static let rowSpacing: CGFloat = 4
        static let compareBadgePadding: CGFloat = 8
        static let animationDuration: TimeInterval = 0.2
        // Hold-to-compare: press forever, the pressing callback does the work
        static let compareMaximumDistance: CGFloat = 60
        static let chipColumnMinimum: CGFloat = 104
    }

    // MARK: Effect strength sliders (v5 F5)
    enum EffectSliderUI {
        // A tick every 5%: VoiceOver adjusts in the same steps
        static let step: Double = 0.05
        static let percentWidth: CGFloat = 56
        static let titleWidth: CGFloat = 84
        static let titleMinScale: CGFloat = 0.7
        static let rowMinHeight: CGFloat = 40
        static let percentScale: Double = 100
    }

    // MARK: Roll grid UI (v5 F6)
    enum RollUI {
        static let columns = 3
        static let gridSpacing: CGFloat = 2
        static let selectionBadgeSize: CGFloat = 24
        static let selectionBadgePadding: CGFloat = 6
        static let selectionRingWidth: CGFloat = 3
        static let selectedDimOpacity: CGFloat = 0.35
        static let toolbarSpacing: CGFloat = 16
        static let emptyIconSize: CGFloat = 40
        static let emptySpacing: CGFloat = 12
        static let emptyButtonCornerRadius: CGFloat = 10
        static let emptyButtonHeight: CGFloat = 46
        static let emptyButtonHorizontalPadding: CGFloat = 24
    }

    // MARK: Diary review screen (v4 F10/F13)
    enum ReviewUI {
        static let stockChipHeight: CGFloat = 44
        static let stockChipHorizontalPadding: CGFloat = 14
        static let stockChipFontSize: CGFloat = 13
        static let stockChipSpacing: CGFloat = 8
        static let downloadButtonSize: CGFloat = 44
        static let downloadIconSize: CGFloat = 17
        static let savedFontSize: CGFloat = 13
        static let savedHorizontalPadding: CGFloat = 12
        static let savedVerticalPadding: CGFloat = 6
        static let overlayOpacity: CGFloat = 0.45
        static let actionButtonHeight: CGFloat = 50
        static let sectionSpacing: CGFloat = 16
        static let effectsMaxHeight: CGFloat = 230
        static let feedbackAnimationDuration: TimeInterval = 0.2
    }

    // MARK: Strip screen UI (project.md §2, screen 4)
    enum StripUI {
        static let swatchDiameter: CGFloat = 30
        static let swatchBorderWidth: CGFloat = 2
        // v4 F8: hairline so a swatch matching the page stays visible
        static let swatchRimWidth: CGFloat = 1
        static let swatchTapTarget: CGFloat = 44
        static let actionCornerRadius: CGFloat = 10
        static let actionFontSize: CGFloat = 13
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25

        // v4 F7 controls card: rows that appear or disappear with the stock
        // (print, effects) fade rather than jump
        static let controlRowAnimationDuration: TimeInterval = 0.2
        // "Effects" group label inside the card (project.md §2 screen 6 label
        // style); the font is .caption so it scales with Dynamic Type
        static let groupLabelTracking: CGFloat = 0.96   // 0.08em at 12pt
    }

    // MARK: First-run walkthrough (v3 F5/F6)
    enum Onboarding {
        static let scrimOpacity: CGFloat = 0.55
        static let bubbleMaxWidth: CGFloat = 260
        static let bubbleCornerRadius: CGFloat = 12
        static let bubbleEdgeInset: CGFloat = 16       // keeps edge-anchored bubbles on screen
        static let bubbleTabGap: CGFloat = 12
        static let arrowLength: CGFloat = 44
        static let arrowStroke: CGFloat = 1.5
        static let stepTransitionDuration: TimeInterval = 0.25
        static let bubbleTitleFontSize: CGFloat = 16
        static let bubbleBodyFontSize: CGFloat = 14
        static let bubbleBodyOpacity: CGFloat = 0.7
        static let bubbleInnerSpacing: CGFloat = 8
        // The tab bar is UIKit-managed, so SwiftUI anchor preferences on
        // .tabItem labels never reach the preference system. The coach-mark
        // anchors come from equal-width proxies laid over the bar's icon band
        // instead; this is that band's UIKit-standard height above the bottom
        // safe-area inset.
        static let tabBarBaseHeight: CGFloat = 49
        // The floating tab bar is inset from the screen edges; the anchor
        // proxies are inset by this fraction of the screen width per side so
        // their thirds line up with the real icon centres.
        // OPEN: fitted against the iPhone 17 Pro simulator — verify on other widths
        static let tabBarEdgeFraction: CGFloat = 0.18
    }

    // MARK: Photo mode edit step (v5 F4)
    enum PhotoEdit {
        // OPEN: the edit screen (PhotoEditView) is the frontend's; until it
        // exists a Photo-mode capture is not presented (so the app can never
        // sit under a cover with no view). Flipped by frontend with lead approval.
        static let presentsEditStep = true
        // Slider drags render once per this pause, last value wins
        static let renderDebounce: TimeInterval = 0.12
        // Download "Saved" confirmation, same as the diary review
        static let downloadSavedConfirmationDuration: TimeInterval = 1.5
        // Roll originals are re-edited and re-encoded later, so they are
        // stored one notch above the capture quality
        static let rollPhotoJPEGQuality: Double = 0.92
    }

    // MARK: Roll (v5 F6)
    enum Roll {
        // OPEN: v5-8 — a Roll photo used in a strip is linked, not copied:
        // the strip renders its current look at generate time
        static let stripUsesLinkedLook = true
        static let maxPhotosPerStrip = Constants.entriesPerStrip
        // Folder (under Documents) holding the Roll originals
        static let photosDirectoryName = "Roll"
        // OPEN: v5-7 — "Clear roll" is separate from "Clear diary"
        static let clearRollIsSeparateFromClearDiary = true
    }

    // MARK: UserDefaults keys
    enum DefaultsKeys {
        static let appearanceMode = "appearanceMode"
        static let captureMode = "captureMode"
        // OPEN: WB persistence TBD — toggle exists in Settings but WB always resets to Auto for now
        static let rememberWhiteBalance = "rememberWhiteBalance"
        static let stripBackground = "stripDefaultBackground"
        // v2 F5 replaced the film-grain toggle with a film stock picker. The old
        // key is still read once so existing installs keep their grain preference.
        static let stripFilmStock = "stripDefaultFilmStock"
        static let stripFilmGrain = "stripDefaultFilmGrain"
        static let stripBlackAndWhite = "stripDefaultBlackAndWhite"
        // v4 F7 strip defaults. stripFilmStock keeps its key; v2 values in it
        // migrate on load (Constants.ImageProcessing.Film.legacyStockMapping).
        static let stripPrintStock = "stripDefaultPrintStock"
        static let stripHalation = "stripDefaultHalation"
        static let stripBloom = "stripDefaultBloom"
        static let stripLightLeak = "stripDefaultLightLeak"
        // v5 F5: haze is the renamed bloom. Its new key is read first; the
        // old bloom key is read once as a fallback (migration).
        static let stripHaze = "stripDefaultHaze"
        static let stripGrain = "stripDefaultGrain"
        static let stripVignette = "stripDefaultVignette"
        // v4 F9: the camera's film stock (raw FilmStock value; missing = Off)
        static let cameraFilmStock = "cameraFilmStock"
    }
}
