import Foundation

// The strip-time film model (v4 F2/F3): a negative curve followed by a print
// curve, baked into a colour cube. Pure Swift with no Core Image, so the same
// function the tests check is the one that produces the pixels.
//
// Units: x = log10(E), E = relative scene-linear exposure (0.18 = mid grey).
// Densities are optical densities; transmittance = 10^-D.

/// One dye layer's characteristic curve: density against log exposure.
///
/// A logistic gives the toe and the shoulder for free and is strictly
/// increasing, which is what a real H&D curve looks like over the range a
/// photo uses. `gamma` is the slope at `x0`, the straight-line contrast.
nonisolated struct FilmCurve: Sendable, Hashable {
    let dMin: Double
    let dMax: Double
    let gamma: Double
    let x0: Double

    /// Logistic steepness chosen so the slope at `x0` equals `gamma`:
    /// the logistic's peak slope is range · k / 4.
    var steepness: Double { 4 * gamma / (dMax - dMin) }

    func density(atLogExposure x: Double) -> Double {
        dMin + (dMax - dMin) / (1 + exp(-steepness * (x - x0)))
    }
}

/// Spectral sensitivity used to turn colour into one exposure for a
/// monochrome render. Applied to linear light.
nonisolated struct SpectralWeights: Sendable, Hashable {
    let r: Double
    let g: Double
    let b: Double

    func luminance(r red: Double, g green: Double, b blue: Double) -> Double {
        r * red + g * green + b * blue
    }
}

nonisolated struct NegativeProfile: Sendable, Hashable {
    let r: FilmCurve
    let g: FilmCurve
    let b: FilmCurve
    let isMonochrome: Bool
    /// How the emulsion sees colour when it renders in monochrome: its own
    /// sensitivity for a B&W stock, panchromatic for a colour stock with the
    /// B&W toggle on (OPEN: v4-7, value in Constants.ImageProcessing.Film).
    let monoWeights: SpectralWeights
    /// The layers' colour separation (v4 F14): saturation and inter-layer
    /// crosstalk, applied to linear light before the curves. Rows sum to
    /// one, so a neutral is untouched and the balanced mid grey survives.
    var colour: ColourMatrix = .identity
    /// Extra shadow openness (v1.2.2 F-122-A), in sRGB units (0…1): a smooth
    /// bump added inside the shadow toe that is zero at black and at the
    /// toe's pivot, peaking a third of the way up, so the deepest black and
    /// everything from mid grey up stay put. 0 (every v1 profile) changes
    /// nothing. See `ShadowToe`.
    var shadowLift: Double = 0

    /// The same profile with another shadow lift (how version 2 opens the
    /// shadows without touching the v1 curves).
    func withShadowLift(_ lift: Double) -> NegativeProfile {
        NegativeProfile(
            r: r, g: g, b: b, isMonochrome: isMonochrome, monoWeights: monoWeights,
            colour: colour, shadowLift: lift
        )
    }
}

/// A 3×3 linear-light colour matrix whose rows each sum to one (v4 F14).
/// Saturation and hue leanings live here because the curves alone can only
/// add contrast-driven saturation and tone-dependent crossovers.
nonisolated struct ColourMatrix: Sendable, Hashable {
    let rr: Double, rg: Double, rb: Double
    let gr: Double, gg: Double, gb: Double
    let br: Double, bg: Double, bb: Double

    static let identity = ColourMatrix(rr: 1, rg: 0, rb: 0, gr: 0, gg: 1, gb: 0, br: 0, bg: 0, bb: 1)

    var isIdentity: Bool { self == .identity }

    /// Scales each colour's distance from its Rec. 709 luminance by `amount`
    /// (1 = unchanged), keeping luminance.
    static func saturation(_ amount: Double) -> ColourMatrix {
        let w = Constants.ImageProcessing.Film.Spectral.panchromatic
        let k = 1 - amount
        return ColourMatrix(
            rr: k * w.r + amount, rg: k * w.g, rb: k * w.b,
            gr: k * w.r, gg: k * w.g + amount, gb: k * w.b,
            br: k * w.r, bg: k * w.g, bb: k * w.b + amount
        )
    }

    /// The green layer picks up `amount` of the blue record: blues lean
    /// teal, oranges lean red; neutrals don't move.
    static func blueIntoGreen(_ amount: Double) -> ColourMatrix {
        ColourMatrix(rr: 1, rg: 0, rb: 0, gr: 0, gg: 1 - amount, gb: amount, br: 0, bg: 0, bb: 1)
    }

    /// The red and blue layers each pick up `amount` of the other: a slight
    /// magenta lean in colours, none in neutrals.
    static func redBlueCrosstalk(_ amount: Double) -> ColourMatrix {
        ColourMatrix(rr: 1 - amount, rg: 0, rb: amount, gr: 0, gg: 1, gb: 0, br: amount, bg: 0, bb: 1 - amount)
    }

    /// `self` applied after `first`.
    func after(_ first: ColourMatrix) -> ColourMatrix {
        ColourMatrix(
            rr: rr * first.rr + rg * first.gr + rb * first.br,
            rg: rr * first.rg + rg * first.gg + rb * first.bg,
            rb: rr * first.rb + rg * first.gb + rb * first.bb,
            gr: gr * first.rr + gg * first.gr + gb * first.br,
            gg: gr * first.rg + gg * first.gg + gb * first.bg,
            gb: gr * first.rb + gg * first.gb + gb * first.bb,
            br: br * first.rr + bg * first.gr + bb * first.br,
            bg: br * first.rg + bg * first.gg + bb * first.bg,
            bb: br * first.rb + bg * first.gb + bb * first.bb
        )
    }

    /// Clamped at zero: a saturation push can drive a channel negative,
    /// which no exposure can be.
    func apply(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        (
            max(rr * r + rg * g + rb * b, 0),
            max(gr * r + gg * g + gb * b, 0),
            max(br * r + bg * g + bb * b, 0)
        )
    }
}

nonisolated struct PrintProfile: Sendable, Hashable {
    let r: FilmCurve
    let g: FilmCurve
    let b: FilmCurve
    /// sRGB-encoded value input black prints at (OPEN: v4-5): the print's
    /// deepest black as seen on screen. Matte keeps a deliberate lift.
    let blackTarget: Double
}

/// Per-channel print exposure offsets: the printer lights of a real enlarger.
nonisolated struct PrintOffsets: Sendable, Equatable {
    let r: Double
    let g: Double
    let b: Double
}

/// The output white/black-point stage after the print (OPEN: v4-5, targets
/// in Constants.ImageProcessing.Film.printWhiteTarget and each print's
/// `blackTarget`).
///
/// With display-referred input treated as scene exposure, a diffuse white
/// only reaches the print's soft toe and lands near 225/255, and black sat
/// on the print's Dmax at ~20/255, so every photo looked grey. This remaps
/// linear output so input white prints at the white target and input black
/// at the print's black target. One affine map for all three channels, so
/// a neutral input stays neutral and the balanced mid grey stays neutral;
/// it is monotonic because the scale is positive.
nonisolated struct OutputNormalisation: Sendable, Equatable {
    let sourceBlack: Double
    let targetBlack: Double
    let scale: Double

    static let identity = OutputNormalisation(sourceBlack: 0, targetBlack: 0, scale: 1)

    func apply(_ linear: Double) -> Double {
        targetBlack + (linear - sourceBlack) * scale
    }
}

/// Shadow toe for one channel (OPEN: v4-5, Constants.ImageProcessing.Film
/// .shadowToe*).
///
/// Why a toe and not new curve numbers: display-referred input puts deep
/// shadows two-plus log units below mid grey, where the negative's toe and
/// the print's Dmax shoulder both flatten, so 0–20% input landed in a few
/// output levels whatever x0, exposureScale or gamma we tried (round 1
/// finding). Moving those would also move the midtones and highlights that
/// give each stock its character.
///
/// Instead, below the mid-grey pivot each channel's response is replaced by
/// a curve in sRGB space whose slope rises from a near-constant `a` to the
/// film's own slope at the pivot: S'(x) = a + (m₁ − a)·tⁿ, t = x / pivot.
/// It starts at the channel's black, meets the film at the pivot with the
/// same value and slope (no kink; nothing at or above mid grey moves, so
/// the balanced mid grey stays neutral), and `a` is solved so the area
/// matches. A high exponent keeps the slope near `a` through the deep
/// shadows — the separation the untouched photo has — and spends the
/// stock's extra contrast just below mid grey, on a print's straight line.
/// Monotone because both slopes are non-negative.
nonisolated struct ShadowToe: Sendable {
    private let pivotInput: Double
    private let black: Double
    private let startSlope: Double
    private let endSlope: Double
    private let exponent: Double
    private let lift: Double

    /// - Parameters:
    ///   - channel: the channel's normalised response, linear in and out.
    ///   - black: where input 0 lands, linear.
    ///   - toeExponent: the model version's `shadowToeExponent`.
    ///   - lift: the stock's `shadowLift`, sRGB units; 0 is the v1 toe.
    init(
        channel: (Double) -> Double,
        black linearBlack: Double,
        toeExponent: Double = Constants.ImageProcessing.Film.shadowToeExponent,
        lift: Double = 0
    ) {
        typealias F = Constants.ImageProcessing.Film
        let pivot = FilmModel.sRGB(fromLinear: F.shadowToePivot)
        // One-sided slope of the film arriving at the pivot, in sRGB terms
        let h = pivot / Double(max(F.shadowToeSlopeSamples, 1))
        let atPivot = FilmModel.extendedSRGB(fromLinear: channel(F.shadowToePivot))
        let below = FilmModel.extendedSRGB(fromLinear: channel(FilmModel.linear(fromSRGB: pivot - h)))
        let filmSlope = max((atPivot - below) / h, 0)
        let blackEncoded = FilmModel.extendedSRGB(fromLinear: linearBlack)
        let secant = max((atPivot - blackEncoded) / pivot, 0)

        var n = max(toeExponent, 1)
        // ∫₀ᵖ S' = secant · pivot  ⇒  a = (secant·(n+1) − m₁) / n
        var a = (secant * (n + 1) - filmSlope) / n
        if a < 0 {
            // Film far steeper than the average: start flat and let the
            // exponent absorb the rest, still meeting value and slope
            a = 0
            n = secant > 0 ? max(filmSlope / secant - 1, 1) : 1
        }
        pivotInput = pivot
        black = blackEncoded
        startSlope = a
        endSlope = filmSlope
        exponent = n
        self.lift = lift
    }

    /// Whether `linear` input is in the toe (below the pivot).
    static func covers(_ linear: Double) -> Bool {
        linear < Constants.ImageProcessing.Film.shadowToePivot
    }

    /// The toe's output for a linear input below the pivot, linear.
    func apply(input linear: Double) -> Double {
        let x = FilmModel.sRGB(fromLinear: linear)
        let t = x / pivotInput
        var encoded = black + startSlope * x
            + (endSlope - startSlope) * pivotInput / (exponent + 1) * pow(t, exponent + 1)
        if lift != 0 {
            // 27/4 · t(1−t)² peaks at 1 (t = 1/3) and is 0 at both ends with
            // zero slope at the pivot, so value and slope still meet the film
            encoded += lift * 6.75 * t * (1 - t) * (1 - t)
        }
        return FilmModel.linear(fromExtendedSRGB: encoded)
    }
}

/// Everything the film model needs that differs between model versions
/// (F-122-B): each stock's negative, each print (with its black target) and
/// the shadow toe. A look carries its `modelVersion`; the pipeline asks for
/// `FilmModelParameters.forVersion(_:)`. The numbers live in
/// `Constants.ImageProcessing.Film` (v1) and `.ModelV2`.
nonisolated struct FilmModelParameters: Sendable {
    let version: Int
    let shadowToeExponent: Double
    private let negatives: [StripCustomization.FilmStock: NegativeProfile]
    private let lab: PrintProfile
    private let cinema: PrintProfile
    private let matte: PrintProfile
    private let projection: PrintProfile

    /// nil for Off, the untouched fast path.
    func negative(for stock: StripCustomization.FilmStock) -> NegativeProfile? { negatives[stock] }

    func print(for printStock: StripCustomization.PrintStock) -> PrintProfile {
        switch printStock {
        case .lab: return lab
        case .cinema: return cinema
        case .matte: return matte
        case .projection: return projection
        }
    }

    static let v1: FilmModelParameters = {
        typealias N = Constants.ImageProcessing.Film.Negative
        typealias P = Constants.ImageProcessing.Film.Print
        return FilmModelParameters(
            version: Constants.ImageProcessing.Film.legacyModelVersion,
            shadowToeExponent: Constants.ImageProcessing.Film.shadowToeExponent,
            negatives: [
                .daylight200: N.daylight200, .portrait400: N.portrait400, .cine500T: N.cine500T,
                .slide100: N.slide100, .mono400: N.mono400, .mono3200: N.mono3200,
            ],
            lab: P.lab, cinema: P.cinema, matte: P.matte, projection: P.projection
        )
    }()

    static let v2: FilmModelParameters = {
        typealias M = Constants.ImageProcessing.Film.ModelV2
        return FilmModelParameters(
            version: Constants.ImageProcessing.Film.currentModelVersion,
            shadowToeExponent: M.shadowToeExponent,
            negatives: [
                .daylight200: M.Negative.daylight200, .portrait400: M.Negative.portrait400,
                .cine500T: M.Negative.cine500T, .slide100: M.Negative.slide100,
                .mono400: M.Negative.mono400, .mono3200: M.Negative.mono3200,
            ],
            lab: M.Print.lab, cinema: M.Print.cinema, matte: M.Print.matte, projection: M.Print.projection
        )
    }()

    static var current: FilmModelParameters { forVersion(Constants.ImageProcessing.Film.currentModelVersion) }

    /// 1 and below read as the v1 set; anything else as the current set
    /// (a version from a newer build still renders).
    static func forVersion(_ version: Int) -> FilmModelParameters {
        version <= Constants.ImageProcessing.Film.legacyModelVersion ? v1 : v2
    }
}

/// The three curve pairs a render actually uses. A monochrome render runs
/// every channel through the red pair.
nonisolated struct FilmChain: Sendable {
    let negative: NegativeProfile
    let print: PrintProfile
    let monochrome: Bool
    let offsets: PrintOffsets
    let normalisation: OutputNormalisation
    let toes: (r: ShadowToe, g: ShadowToe, b: ShadowToe)
    /// Linear gain (2^EV, v5.2 F-EXP) on the scene light before the negative
    /// curve, so over-exposure rolls off through the shoulder instead of
    /// clipping. 1 changes nothing: the white and black points stay solved
    /// at an exposure of 0.
    let exposureGain: Double

    init(
        negative: NegativeProfile,
        print: PrintProfile,
        monochrome: Bool,
        exposureGain: Double = 1,
        toeExponent: Double = Constants.ImageProcessing.Film.shadowToeExponent
    ) {
        self.exposureGain = exposureGain
        let isMono = monochrome || negative.isMonochrome
        let used = isMono
            ? NegativeProfile(r: negative.r, g: negative.r, b: negative.r, isMonochrome: true, monoWeights: negative.monoWeights, colour: .identity, shadowLift: negative.shadowLift)
            : negative
        // A monochrome render takes luminance, so the colour matrix has
        // nothing to act on there
        let usedPrint = isMono
            ? PrintProfile(r: print.r, g: print.r, b: print.r, blackTarget: print.blackTarget)
            : print
        self.negative = used
        self.print = usedPrint
        self.monochrome = isMono
        let offsets = FilmModel.balancedPrintOffsets(negative: used, print: usedPrint)
        self.offsets = offsets
        let normalisation = FilmModel.outputNormalisation(negative: used, print: usedPrint, offsets: offsets)
        self.normalisation = normalisation

        // Each channel's black keeps its share of the neutral black, so a
        // print's tinted black (cinema's cool blue) survives and the
        // luminance of input black is exactly the print's black target
        func film(_ negative: FilmCurve, _ print: FilmCurve, _ offset: Double) -> (Double) -> Double {
            { normalisation.apply(FilmModel.printed(linear: $0, negative: negative, print: print, offset: offset)) }
        }
        let filmR = film(used.r, usedPrint.r, offsets.r)
        let filmG = film(used.g, usedPrint.g, offsets.g)
        let filmB = film(used.b, usedPrint.b, offsets.b)
        let neutralBlack = normalisation.apply(
            FilmModel.neutralPrinted(linear: 0, negative: used, print: usedPrint, offsets: offsets))
        let targetBlack = FilmModel.linear(fromSRGB: usedPrint.blackTarget)
        func black(_ channel: (Double) -> Double) -> Double {
            neutralBlack > 0 ? targetBlack * channel(0) / neutralBlack : targetBlack
        }
        toes = (
            ShadowToe(channel: filmR, black: black(filmR), toeExponent: toeExponent, lift: used.shadowLift),
            ShadowToe(channel: filmG, black: black(filmG), toeExponent: toeExponent, lift: used.shadowLift),
            ShadowToe(channel: filmB, black: black(filmB), toeExponent: toeExponent, lift: used.shadowLift)
        )
    }

    /// Normalised linear output for one linear input per channel.
    func render(r rIn: Double, g gIn: Double, b bIn: Double) -> (r: Double, g: Double, b: Double) {
        // Rows of the colour matrix sum to 1, so the gain commutes with it
        let r = rIn * exposureGain, g = gIn * exposureGain, b = bIn * exposureGain
        if monochrome {
            let luminance = negative.monoWeights.luminance(r: r, g: g, b: b)
            let value = channel(luminance, negative.r, print.r, offsets.r, toes.r)
            return (value, value, value)
        }
        let exposed = negative.colour.apply(r: r, g: g, b: b)
        return (
            channel(exposed.r, negative.r, print.r, offsets.r, toes.r),
            channel(exposed.g, negative.g, print.g, offsets.g, toes.g),
            channel(exposed.b, negative.b, print.b, offsets.b, toes.b)
        )
    }

    private func channel(_ value: Double, _ negative: FilmCurve, _ print: FilmCurve, _ offset: Double, _ toe: ShadowToe) -> Double {
        if ShadowToe.covers(value) {
            return toe.apply(input: value)
        }
        return normalisation.apply(FilmModel.printed(linear: value, negative: negative, print: print, offset: offset))
    }
}

nonisolated enum FilmModel {

    // MARK: Transfer functions

    // The cube is indexed in gamma-encoded sRGB (CIColorCubeWithColorSpace
    // with an sRGB space), but the film maths needs linear light.
    static func linear(fromSRGB value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func sRGB(fromLinear value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    /// sRGB encoding without the clamp: the linear segment continues below
    /// zero, so the shadow toe's arithmetic never folds at black.
    static func extendedSRGB(fromLinear value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    static func linear(fromExtendedSRGB value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// Log exposure of a linear value. Display-referred photos treated as
    /// relative scene exposure is an accepted v4 approximation (spec §F2);
    /// the floor stops pure black from becoming −∞.
    static func logExposure(linear value: Double) -> Double {
        typealias F = Constants.ImageProcessing.Film
        return log10(max(value * F.exposureScale, F.minimumExposure))
    }

    // MARK: Negative → print

    /// One channel through the whole chain. More negative density means less
    /// light reaches the print, so the print sees `−D_neg + offset`.
    static func printed(
        linear value: Double,
        negative: FilmCurve,
        print: FilmCurve,
        offset: Double
    ) -> Double {
        let negativeDensity = negative.density(atLogExposure: logExposure(linear: value))
        let printDensity = print.density(atLogExposure: offset - negativeDensity)
        return pow(10, -printDensity)
    }

    /// Solves the print offset that maps mid grey to `target` for one channel.
    ///
    /// Output falls monotonically as the offset rises (more print exposure,
    /// denser print), so bisection always converges. Solving rather than
    /// hand-tuning keeps the print from adding a colour cast of its own: the
    /// stock's character comes from its curves, not from the printer lights.
    static func balancedPrintOffset(
        negative: FilmCurve,
        print: FilmCurve,
        midGrey: Double = Constants.ImageProcessing.Film.midGrey,
        target: Double = Constants.ImageProcessing.Film.printMidGreyTarget
    ) -> Double {
        typealias F = Constants.ImageProcessing.Film
        var low = -F.printOffsetSearchRange
        var high = F.printOffsetSearchRange
        for _ in 0..<F.printOffsetIterations {
            let middle = (low + high) / 2
            if printed(linear: midGrey, negative: negative, print: print, offset: middle) > target {
                low = middle
            } else {
                high = middle
            }
        }
        return (low + high) / 2
    }

    /// Solves the white/black-point stage on the neutral response: input
    /// black and white run through all three channels, reduced to one value
    /// each with Rec. 709 weights so a crossover tint survives the remap.
    static func outputNormalisation(
        negative: NegativeProfile,
        print: PrintProfile,
        offsets: PrintOffsets
    ) -> OutputNormalisation {
        typealias F = Constants.ImageProcessing.Film
        let black = neutralPrinted(linear: 0, negative: negative, print: print, offsets: offsets)
        let white = neutralPrinted(linear: 1, negative: negative, print: print, offsets: offsets)
        let whiteTarget = linear(fromSRGB: F.printWhiteTarget)
        let blackTarget = linear(fromSRGB: print.blackTarget)
        guard white > black, whiteTarget > blackTarget else { return .identity }
        return OutputNormalisation(
            sourceBlack: black,
            targetBlack: blackTarget,
            scale: (whiteTarget - blackTarget) / (white - black)
        )
    }

    /// The print's raw neutral response: one input through all three
    /// channels, reduced with Rec. 709 weights so a crossover tint counts.
    static func neutralPrinted(
        linear input: Double,
        negative: NegativeProfile,
        print: PrintProfile,
        offsets: PrintOffsets
    ) -> Double {
        Constants.ImageProcessing.Film.Spectral.panchromatic.luminance(
            r: printed(linear: input, negative: negative.r, print: print.r, offset: offsets.r),
            g: printed(linear: input, negative: negative.g, print: print.g, offset: offsets.g),
            b: printed(linear: input, negative: negative.b, print: print.b, offset: offsets.b)
        )
    }

    static func balancedPrintOffsets(negative: NegativeProfile, print: PrintProfile) -> PrintOffsets {
        if negative.isMonochrome {
            // A monochrome render uses one curve pair for all three channels
            let offset = balancedPrintOffset(negative: negative.r, print: print.r)
            return PrintOffsets(r: offset, g: offset, b: offset)
        }
        return PrintOffsets(
            r: balancedPrintOffset(negative: negative.r, print: print.r),
            g: balancedPrintOffset(negative: negative.g, print: print.g),
            b: balancedPrintOffset(negative: negative.b, print: print.b)
        )
    }
}

// MARK: - Colour cube

nonisolated enum FilmLUT {

    /// Float32 RGBA cube for `CIColorCubeWithColorSpace`, red varying fastest.
    /// Lattice coordinates and outputs are gamma-encoded sRGB.
    ///
    /// - Parameter monochrome: render every lattice point through the red
    ///   curve pair from the negative's spectral luminance. True for a B&W
    ///   stock, or a colour stock with the B&W toggle on (OPEN: v4-7).
    static func cube(
        negative: NegativeProfile,
        print: PrintProfile,
        monochrome: Bool,
        exposureGain: Double = 1,
        parameters: FilmModelParameters = .current,
        dimension: Int = Constants.ImageProcessing.Film.lutDimension
    ) -> Data {
        guard dimension >= 2 else { return Data() }
        let chain = FilmChain(
            negative: negative, print: print, monochrome: monochrome,
            exposureGain: exposureGain, toeExponent: parameters.shadowToeExponent
        )

        let step = 1 / Double(dimension - 1)
        let linearAxis = (0..<dimension).map { FilmModel.linear(fromSRGB: Double($0) * step) }
        var values = [Float](repeating: 1, count: dimension * dimension * dimension * 4)

        if chain.monochrome || !chain.negative.colour.isIdentity {
            // Luminance (or a colour matrix) mixes all three inputs, so every
            // lattice point is evaluated
            for b in 0..<dimension {
                for g in 0..<dimension {
                    for r in 0..<dimension {
                        let out = chain.render(r: linearAxis[r], g: linearAxis[g], b: linearAxis[b])
                        let index = ((b * dimension + g) * dimension + r) * 4
                        values[index] = Float(FilmModel.sRGB(fromLinear: out.r))
                        values[index + 1] = Float(FilmModel.sRGB(fromLinear: out.g))
                        values[index + 2] = Float(FilmModel.sRGB(fromLinear: out.b))
                    }
                }
            }
        } else {
            // Colour layers are independent, so three 1-D tables fill the cube:
            // dimension evaluations per channel instead of dimension³
            let rendered = linearAxis.map { chain.render(r: $0, g: $0, b: $0) }
            let red = rendered.map { Float(FilmModel.sRGB(fromLinear: $0.r)) }
            let green = rendered.map { Float(FilmModel.sRGB(fromLinear: $0.g)) }
            let blue = rendered.map { Float(FilmModel.sRGB(fromLinear: $0.b)) }
            for b in 0..<dimension {
                for g in 0..<dimension {
                    for r in 0..<dimension {
                        let index = ((b * dimension + g) * dimension + r) * 4
                        values[index] = red[r]
                        values[index + 1] = green[g]
                        values[index + 2] = blue[b]
                    }
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: Cache

    struct Key: Hashable, Sendable {
        let negative: NegativeProfile
        let print: PrintProfile
        let monochrome: Bool
        let exposureGain: Double
        /// Stock + print + B&W + model version (F-122-B): the version and its
        /// toe both key the cube, so two versions never share one.
        let modelVersion: Int
        let toeExponent: Double
        let dimension: Int
    }

    /// A 64³ cube is 4 MB, and every toggle re-renders four slots, so cubes
    /// are built once and reused. Keyed on the profiles themselves rather than
    /// the UI enums so the cache cannot go stale when a stock's numbers change.
    static func cachedCube(
        negative: NegativeProfile,
        print: PrintProfile,
        monochrome: Bool,
        exposureGain: Double = 1,
        parameters: FilmModelParameters = .current,
        dimension: Int = Constants.ImageProcessing.Film.lutDimension
    ) -> Data {
        let key = Key(
            negative: negative, print: print, monochrome: monochrome, exposureGain: exposureGain,
            modelVersion: parameters.version, toeExponent: parameters.shadowToeExponent, dimension: dimension
        )
        if let cached = cache.value(for: key) {
            return cached
        }
        // Built outside the lock: two threads racing on the same key both
        // build an identical cube, which is cheaper than serialising renders
        let built = cube(
            negative: negative, print: print, monochrome: monochrome,
            exposureGain: exposureGain, parameters: parameters, dimension: dimension
        )
        cache.insert(built, for: key)
        return built
    }

    private static let cache = CubeCache<Key>(limit: Constants.ImageProcessing.Film.lutCacheLimit)
}

/// Lock-protected, insertion-ordered cache with a size cap.
nonisolated private final class CubeCache<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Key: Data] = [:]
    private var order: [Key] = []
    private let limit: Int

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func value(for key: Key) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func insert(_ data: Data, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        guard entries[key] == nil else { return }
        entries[key] = data
        order.append(key)
        // Drop the oldest: a user explores a few looks at a time, and every
        // cube can be rebuilt deterministically
        while order.count > limit {
            entries[order.removeFirst()] = nil
        }
    }
}

// MARK: - Seeded randomness (v4 F4–F6)

/// SplitMix64: tiny, fast and fully specified, so a strip re-renders
/// identically on every device and OS version. `Hasher` is randomised per
/// process and `SystemRandomNumberGenerator` is not seedable, so neither will do.
nonisolated struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// A child seed for one effect. Each effect draws from its own stream, so
    /// switching one effect on or off never reshuffles another.
    static func derive(_ seed: UInt64, salt: UInt64) -> UInt64 {
        var generator = SeededRandom(seed: seed ^ salt)
        return generator.next()
    }
}

// MARK: - Grain v2 (v4 F5)

/// How a stock's grain is built (v4 F14): the two octaves' weights, the
/// coarse octave's size, an overall size factor and where in the density
/// range grain shows.
nonisolated struct GrainProfile: Sendable, Hashable {
    let fineWeight: Double
    let coarseWeight: Double
    let coarseSizeMultiplier: Double
    let sizeScale: Double
    /// Amplitude weight over normalised print density, paper white (0) to
    /// the densest black (1); see `FilmGrain.weight(atDensity:curve:)`.
    let densityCurve: [Double]
}

nonisolated enum FilmGrain {

    /// Grain amplitude weight for a normalised print density (0 = paper
    /// white, 1 = densest), read off `Film.grainDensityCurve` with linear
    /// interpolation between its evenly spaced control points.
    static func weight(
        atDensity density: Double,
        curve: [Double] = Constants.ImageProcessing.Film.grainDensityCurve
    ) -> Double {
        guard let first = curve.first else { return 0 }
        guard curve.count > 1 else { return first }
        let position = min(max(density, 0), 1) * Double(curve.count - 1)
        let lower = min(Int(position), curve.count - 2)
        let fraction = position - Double(lower)
        return curve[lower] + (curve[lower + 1] - curve[lower]) * fraction
    }

    /// Normalised density of a linear output value: −log10(L) over the
    /// print's useful density range, clamped to 0…1.
    static func normalisedDensity(ofLinear value: Double) -> Double {
        typealias F = Constants.ImageProcessing.Film
        let density = -log10(max(value, F.minimumExposure))
        return min(max(density / F.grainDensityRange, 0), 1)
    }

    /// Lookup table for `CIColorCurves` in sRGB: entry i is the amplitude
    /// weight for the sRGB-encoded luminance i/(count−1). Stored sRGB-encoded,
    /// because CIColorCurves hands its output back through the same space.
    /// Indexing by sRGB spends the entries evenly across what the eye sees,
    /// rather than crowding them into the highlights.
    static func amplitudeTable(
        count: Int = Constants.ImageProcessing.Film.grainAmplitudeTableSize,
        curve: [Double] = Constants.ImageProcessing.Film.grainDensityCurve
    ) -> [Float] {
        guard count >= 2 else { return [] }
        return (0..<count).map { index in
            let encoded = Double(index) / Double(count - 1)
            let density = normalisedDensity(ofLinear: FilmModel.linear(fromSRGB: encoded))
            let weight = min(max(self.weight(atDensity: density, curve: curve), 0), 1)
            return Float(FilmModel.sRGB(fromLinear: weight))
        }
    }

    static func intensity(forISO iso: Int) -> Double {
        interpolated(Constants.ImageProcessing.Film.grainIntensityByISO, at: iso)
    }

    static func sizePixels(forISO iso: Int) -> Double {
        interpolated(Constants.ImageProcessing.Film.grainSizePixels, at: iso)
    }

    // Speeds between table entries interpolate in log2(ISO), i.e. per stop
    private static func interpolated(_ table: [Int: Double], at iso: Int) -> Double {
        if let exact = table[iso] { return exact }
        let speeds = table.keys.sorted()
        guard let lowest = speeds.first, let highest = speeds.last else { return 0 }
        if iso <= lowest { return table[lowest] ?? 0 }
        if iso >= highest { return table[highest] ?? 0 }
        guard
            let upper = speeds.first(where: { $0 > iso }),
            let lower = speeds.last(where: { $0 < iso }),
            let low = table[lower], let high = table[upper]
        else {
            return 0
        }
        let fraction = (log2(Double(iso)) - log2(Double(lower))) / (log2(Double(upper)) - log2(Double(lower)))
        return low + (high - low) * fraction
    }
}

// MARK: - Light leak placement (v4 F6)

/// One warm glow of a light leak, in slot pixels (origin bottom-left, as
/// Core Image counts).
nonisolated struct LightLeakSpot: Sendable, Equatable {
    let centreX: Double
    let centreY: Double
    let radius: Double
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated enum LightLeak {

    /// Where the leak falls for a seed: an edge picked by the seeded RNG,
    /// a point along it, and glows centred just outside the frame, the way
    /// light fogs film from a gap in the camera back. Pure, so placement is
    /// testable and identical on every render of the same slot.
    static func spots(seed: UInt64, width: Double, height: Double) -> [LightLeakSpot] {
        typealias F = Constants.ImageProcessing.Film
        guard width > 0, height > 0, !F.lightLeakColors.isEmpty else { return [] }
        var random = SeededRandom(seed: seed)
        let edge = Int(random.next() % 4)
        let span = F.lightLeakAlongRange
        let along = span.lowerBound + random.nextUnit() * (span.upperBound - span.lowerBound)
        let size = max(width, height)
        let outside = F.lightLeakOutsideFraction * size

        return F.lightLeakColors.enumerated().map { index, colour in
            // Each further glow sits a little further along the edge and is
            // smaller, so two colours read as one streak rather than a target
            let shift = Double(index) * F.lightLeakSpotSpacing
            let position = min(max(along + shift, 0), 1)
            let (x, y): (Double, Double)
            switch edge {
            case 0: (x, y) = (-outside, position * height)              // left
            case 1: (x, y) = (width + outside, position * height)       // right
            case 2: (x, y) = (position * width, -outside)               // bottom
            default: (x, y) = (position * width, height + outside)      // top
            }
            let radius = size * F.lightLeakRadiusFraction * pow(F.lightLeakSpotFalloff, Double(index))
            return LightLeakSpot(centreX: x, centreY: y, radius: radius, red: colour.r, green: colour.g, blue: colour.b)
        }
    }
}

// MARK: Shadows, Highlights and Contrast (v1.2.2 F-122-C, F-122-J)

/// The Shadows, Highlights and Contrast tools' curve: one monotone map of the
/// print's encoded output, applied right after the film cube. Shadows acts
/// only below the encoded mid grey, Highlights only above it, so the two never
/// interact and the curve stays monotone whenever each half does. Contrast
/// runs first, so Shadows and Highlights can still open what it crushed.
nonisolated enum ToneStage {
    typealias T = Constants.ImageProcessing.Film.ToneControl

    /// The encoded value the print puts mid grey at.
    static let pivot: Double = T.pivotEncoded

    /// Encoded `value` (0...1) through the curve; `shadows` and `highlights`
    /// and `contrast` are -1...+1 (the tools' -100...+100). All 0 returns `value`.
    static func apply(_ input: Double, shadows: Double, highlights: Double, contrast: Double = 0) -> Double {
        let value = contrast == 0 ? input : contrasted(input, contrast)
        var out = value
        let t = min(max(value / pivot, 0), 1)
        if shadows > 0 {
            // Opens the shadows and lifts the black a little
            out += shadows * T.shadowOpenAmount * (1 - t) * (1 - t) * (T.shadowOpenBlackShare + T.shadowOpenShape * t)
        } else if shadows < 0 {
            // A share of the tone, never a subtraction: 0 stays 0 and deep
            // tones stay distinct instead of clipping
            out *= 1 - -shadows * T.shadowDeepenAmount * (1 - t) * (1 - t)
        }
        let u = min(max((value - pivot) / (1 - pivot), 0), 1)
        let bump = 6.75 * u * u * (1 - u)
        if highlights > 0 {
            out += highlights * T.highlightBoostAmount * bump
        } else if highlights < 0 {
            let smooth = u * u * (3 - 2 * u)
            out -= -highlights * T.highlightRecoverAmount
                * (T.highlightRecoverBumpShare * bump + (1 - T.highlightRecoverBumpShare) * smooth)
        }
        return out
    }

    /// + : an S-curve around mid grey with 0 and 1 fixed, flat at both ends,
    /// so the darkest tones reach true black and the brightest pure white.
    /// - : the range closes toward mid grey, a faded print.
    private static func contrasted(_ value: Double, _ contrast: Double) -> Double {
        let x = min(max(value, 0), 1)
        guard contrast > 0 else {
            return pivot + (x - pivot) * (1 - -contrast * T.contrastFlattenAmount)
        }
        let steepness = 1 + contrast * T.contrastBoostAmount
        let dark = pow(x, steepness)
        return dark / (dark + pow(1 - x, steepness))
    }

    /// Float32 RGB table for `CIColorCurves`: the same curve in all three channels.
    static func table(shadows: Double, highlights: Double, contrast: Double = 0) -> Data {
        let count = T.tableSize
        var floats: [Float] = []
        floats.reserveCapacity(count * 3)
        for index in 0..<count {
            let input = Double(index) / Double(count - 1)
            let output = Float(min(max(apply(input, shadows: shadows, highlights: highlights, contrast: contrast), 0), 1))
            floats.append(contentsOf: [output, output, output])
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

// MARK: Saturation (v1.2.2 F-122-J)

/// The Saturation tool's colour map, in the print's encoded output. Down, every
/// colour moves evenly toward its own grey, and -1 is that grey. Up, muted
/// colours gain more than vivid ones and skin tones hold back, so faces don't
/// turn orange; the hue is kept, and no channel is pushed past 0 or 1.
nonisolated enum SaturationStage {
    typealias S = Constants.ImageProcessing.Film.Saturation

    /// `amount` is -1...+1 (the tool's -100...+100); 0 returns the colour as is.
    static func apply(r: Double, g: Double, b: Double, amount: Double) -> (r: Double, g: Double, b: Double) {
        guard amount != 0 else { return (r, g, b) }
        let grey = S.lumaRed * r + S.lumaGreen * g + S.lumaBlue * b
        var factor = 1 + amount
        if amount > 0 {
            let chroma = max(r, g, b) - min(r, g, b)
            let muted = 1 - S.vividRestraint * chroma
            let skin = 1 - S.skinProtection * skinWeight(r: r, g: g, b: b)
            factor = 1 + amount * S.boostAmount * muted * skin
            for channel in [r, g, b] where channel != grey {
                let room = channel > grey ? (1 - grey) / (channel - grey) : grey / (grey - channel)
                factor = min(factor, room)
            }
        }
        func out(_ channel: Double) -> Double { min(max(grey + (channel - grey) * factor, 0), 1) }
        return (out(r), out(g), out(b))
    }

    /// 1 for a colour squarely in the skin range, fading to 0 by hue and for
    /// colours too vivid to be skin.
    static func skinWeight(r: Double, g: Double, b: Double) -> Double {
        let high = max(r, g, b)
        let chroma = high - min(r, g, b)
        guard chroma > 0 else { return 0 }
        let sextant: Double
        if high == r {
            sextant = (g - b) / chroma
        } else if high == g {
            sextant = (b - r) / chroma + 2
        } else {
            sextant = (r - g) / chroma + 4
        }
        let hue = (sextant * 60 + 360).truncatingRemainder(dividingBy: 360)
        let offset = abs(hue - S.skinHueDegrees)
        let distance = min(offset, 360 - offset) / S.skinHueWidthDegrees
        let fade = min(max((chroma - S.skinChromaFadeStart) / (S.skinChromaFadeEnd - S.skinChromaFadeStart), 0), 1)
        return exp(-0.5 * distance * distance) * (1 - fade * fade * (3 - 2 * fade))
    }

    /// The map baked for `CIColorCube`: Float32 RGBA, red varying fastest.
    static func cube(amount: Double, dimension: Int = S.cubeDimension) -> Data {
        var floats: [Float] = []
        floats.reserveCapacity(dimension * dimension * dimension * 4)
        let last = Double(dimension - 1)
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let colour = apply(r: Double(red) / last, g: Double(green) / last, b: Double(blue) / last, amount: amount)
                    floats.append(contentsOf: [Float(colour.r), Float(colour.g), Float(colour.b), 1])
                }
            }
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Cached per slider step, since a drag revisits the same few values.
    static func cachedCube(amount: Double) -> Data {
        let key = Int((amount * 1000).rounded())
        if let cached = cache.value(for: key) { return cached }
        let built = cube(amount: amount)
        cache.insert(built, for: key)
        return built
    }

    private static let cache = CubeCache<Int>(limit: S.cacheLimit)
}
