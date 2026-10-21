import Foundation
import Testing
@testable import frmr

// v4 F2/F3: the pure film model. No Core Image here — these check the same
// functions that fill the colour cube.
struct FilmModelTests {

    private typealias Film = Constants.ImageProcessing.Film

    private static let negatives: [(String, NegativeProfile)] = [
        ("daylight200", Film.Negative.daylight200),
        ("portrait400", Film.Negative.portrait400),
        ("cine500T", Film.Negative.cine500T),
        ("slide100", Film.Negative.slide100),
        ("mono400", Film.Negative.mono400),
        ("mono3200", Film.Negative.mono3200),
    ]

    private static let prints: [(String, PrintProfile)] = [
        ("lab", Film.Print.lab),
        ("cinema", Film.Print.cinema),
        ("matte", Film.Print.matte),
        ("projection", Film.Print.projection),
    ]

    private static var allCurves: [(String, FilmCurve)] {
        negatives.flatMap { name, profile in
            [("\(name).r", profile.r), ("\(name).g", profile.g), ("\(name).b", profile.b)]
        } + prints.flatMap { name, profile in
            [("\(name).r", profile.r), ("\(name).g", profile.g), ("\(name).b", profile.b)]
        }
    }

    // Small enough to keep the full-lattice tests quick; the maths does not
    // depend on the dimension
    private static let testDimension = 17

    // MARK: Curves

    @Test func everyCurveIsStrictlyIncreasing() {
        for (name, curve) in Self.allCurves {
            var previous = curve.density(atLogExposure: -3)
            for step in 1...400 {
                let x = -3 + Double(step) * 0.01
                let density = curve.density(atLogExposure: x)
                #expect(density > previous, "\(name) not increasing at x = \(x)")
                previous = density
            }
        }
    }

    @Test func densityAtTheSpeedPointIsTheMidpointWithSlopeGamma() {
        for (name, curve) in Self.allCurves {
            let midpoint = (curve.dMin + curve.dMax) / 2
            #expect(abs(curve.density(atLogExposure: curve.x0) - midpoint) < 1e-12, "\(name) midpoint")

            let h = 1e-4
            let slope = (curve.density(atLogExposure: curve.x0 + h) - curve.density(atLogExposure: curve.x0 - h)) / (2 * h)
            #expect(abs(slope - curve.gamma) < 1e-6, "\(name) slope \(slope) ≠ gamma \(curve.gamma)")
        }
    }

    @Test func curvesStayBetweenTheirDensityLimits() {
        for (name, curve) in Self.allCurves {
            for x in stride(from: -6.0, through: 6.0, by: 0.5) {
                let density = curve.density(atLogExposure: x)
                #expect(density >= curve.dMin && density <= curve.dMax, "\(name) at \(x)")
            }
        }
    }

    // MARK: Print balancing

    @Test func balancedPrintKeepsMidGreyNeutralForEveryStockAndPrint() {
        for (negativeName, negative) in Self.negatives {
            for (printName, print) in Self.prints {
                let offsets = FilmModel.balancedPrintOffsets(negative: negative, print: print)
                // A monochrome render runs every channel through the red pair
                let mono = negative.isMonochrome
                let r = FilmModel.sRGB(fromLinear: FilmModel.printed(
                    linear: Film.midGrey, negative: negative.r, print: print.r, offset: offsets.r))
                let g = FilmModel.sRGB(fromLinear: FilmModel.printed(
                    linear: Film.midGrey, negative: mono ? negative.r : negative.g,
                    print: mono ? print.r : print.g, offset: offsets.g))
                let b = FilmModel.sRGB(fromLinear: FilmModel.printed(
                    linear: Film.midGrey, negative: mono ? negative.r : negative.b,
                    print: mono ? print.r : print.b, offset: offsets.b))
                let pair = "\(negativeName) + \(printName)"
                #expect(abs(r - b) < 1.0 / 255, "\(pair): r \(r) b \(b)")
                #expect(abs(r - g) < 1.0 / 255, "\(pair): r \(r) g \(g)")
                let target = FilmModel.sRGB(fromLinear: Film.printMidGreyTarget)
                #expect(abs(g - target) < 1.0 / 255, "\(pair): mid grey lands at \(g), not \(target)")
            }
        }
    }

    @Test func balancingSolvesForTheRequestedTarget() {
        let negative = Film.Negative.portrait400.g
        let print = Film.Print.lab.g
        for target in [0.1, 0.18, 0.3] {
            let offset = FilmModel.balancedPrintOffset(negative: negative, print: print, target: target)
            let output = FilmModel.printed(linear: Film.midGrey, negative: negative, print: print, offset: offset)
            #expect(abs(output - target) < 1e-9)
        }
    }

    @Test func theChainIsMonotonicInExposure() {
        // Scene brighter → negative denser → less light on the print →
        // lighter print. Any sign slip in the chain inverts the image.
        for (name, negative) in Self.negatives {
            let print = negative.isMonochrome ? Film.Print.lab : Film.Print.cinema
            let offsets = FilmModel.balancedPrintOffsets(negative: negative, print: print)
            var previous = -1.0
            for step in 0...100 {
                let output = FilmModel.printed(
                    linear: Double(step) / 100, negative: negative.g, print: print.g, offset: offsets.g)
                #expect(output > previous, "\(name) at \(step)")
                previous = output
            }
        }
    }

    // Replaces v2's warmStocksPushRedAboveBlueAndNeutralStocksDoNot: with a
    // balanced print, a stock's colour lives in its crossover, so it shows
    // away from mid grey rather than as a flat cast.
    @Test func crossoversGiveDaylightWarmHighlightsAndCineCoolHighlights() {
        func highlight(_ negative: NegativeProfile, _ print: PrintProfile) -> (r: Double, b: Double) {
            let offsets = FilmModel.balancedPrintOffsets(negative: negative, print: print)
            let light = FilmModel.linear(fromSRGB: 0.8)
            return (
                FilmModel.printed(linear: light, negative: negative.r, print: print.r, offset: offsets.r),
                FilmModel.printed(linear: light, negative: negative.b, print: print.b, offset: offsets.b)
            )
        }
        let daylight = highlight(Film.Negative.daylight200, Film.Print.lab)
        let cine = highlight(Film.Negative.cine500T, Film.Print.cinema)
        #expect(daylight.r > daylight.b, "Daylight 200 highlights should read warm")
        #expect(cine.b > cine.r, "Cine 500T highlights should read cool")
    }

    // MARK: Output normalisation (v4-5 lead decision)

    private static var allChains: [(String, FilmChain)] {
        negatives.flatMap { negativeName, negative in
            prints.flatMap { printName, print in
                [false, true].map { mono in
                    ("\(negativeName) + \(printName), mono \(mono)", FilmChain(negative: negative, print: print, monochrome: mono))
                }
            }
        }
    }

    @Test func inputWhitePrintsAtTheWhiteTargetForEveryStockAndPrint() {
        for (label, chain) in Self.allChains {
            let white = chain.render(r: 1, g: 1, b: 1)
            let luminance = Film.Spectral.panchromatic.luminance(r: white.r, g: white.g, b: white.b)
            let encoded = FilmModel.sRGB(fromLinear: luminance)
            #expect(abs(encoded - Film.printWhiteTarget) < 1.0 / 255, "\(label): white at \(encoded)")
        }
    }

    private static func encodedLuminance(_ chain: FilmChain, _ input: Double) -> Double {
        let out = chain.render(r: input, g: input, b: input)
        return FilmModel.sRGB(fromLinear: Film.Spectral.panchromatic.luminance(r: out.r, g: out.g, b: out.b))
    }

    @Test func normalisedChainIsMonotonic() {
        for (label, chain) in Self.allChains {
            var previous = chain.render(r: 0, g: 0, b: 0)
            for step in 1...400 {
                let v = FilmModel.linear(fromSRGB: Double(step) / 400)
                let next = chain.render(r: v, g: v, b: v)
                #expect(next.r > previous.r && next.g > previous.g && next.b > previous.b, "\(label) at \(v)")
                previous = next
            }
        }
    }

    // MARK: Black targets and shadow toe (v4-5, sample-sheet finding)

    @Test func inputBlackPrintsAtEachPrintsBlackTarget() {
        let targets: [(String, PrintProfile, Double)] = [
            ("lab", Film.Print.lab, 6), ("cinema", Film.Print.cinema, 4),
            ("projection", Film.Print.projection, 3), ("matte", Film.Print.matte, 28),
        ]
        for (name, print, expected) in targets {
            #expect(abs(print.blackTarget * 255 - expected) < 0.01)
            for (negativeName, negative) in Self.negatives {
                for mono in [false, true] {
                    let chain = FilmChain(negative: negative, print: print, monochrome: mono)
                    let black = Self.encodedLuminance(chain, 0) * 255
                    #expect(abs(black - expected) <= 1, "\(negativeName) + \(name), mono \(mono): black \(black)/255")
                }
            }
        }
    }

    /// Shadow separation against the untouched photo (identity): the ratio
    /// of output to input steps between sRGB 0.02, 0.05, 0.10 and 0.20.
    /// At most 25% compression for every stock on its default print.
    @Test func shadowsKeepTheirSeparationOnEachStocksDefaultPrint() {
        let defaults: [(String, NegativeProfile, PrintProfile)] = [
            ("Daylight 200", Film.Negative.daylight200, Film.Print.lab),
            ("Portrait 400", Film.Negative.portrait400, Film.Print.lab),
            ("Cine 500T", Film.Negative.cine500T, Film.Print.cinema),
            ("Slide 100", Film.Negative.slide100, Film.Print.projection),
            ("Mono 400", Film.Negative.mono400, Film.Print.lab),
            ("Mono 3200", Film.Negative.mono3200, Film.Print.lab),
        ]
        let points = [0.02, 0.05, 0.10, 0.20]
        for (label, negative, print) in defaults {
            let chain = FilmChain(negative: negative, print: print, monochrome: false)
            for (low, high) in zip(points, points.dropFirst()) {
                let ratio = (Self.encodedLuminance(chain, FilmModel.linear(fromSRGB: high))
                    - Self.encodedLuminance(chain, FilmModel.linear(fromSRGB: low))) / (high - low)
                #expect(ratio >= 0.75, "\(label): \(low)–\(high) separation \(ratio) of Off's")
            }
        }
    }

    @Test func theToeLeavesMidGreyAndAboveUntouched() {
        for (label, chain) in Self.allChains where !chain.monochrome {
            for input in [Film.midGrey, 0.3, 0.6, 1.0] {
                let toned = chain.render(r: input, g: input, b: input).g
                let film = chain.normalisation.apply(FilmModel.printed(
                    linear: input, negative: chain.negative.g, print: chain.print.g, offset: chain.offsets.g))
                #expect(abs(toned - film) < 1e-12, "\(label) at \(input)")
            }
        }
    }

    @Test func normalisedMidGreyStaysNeutral() {
        for (label, chain) in Self.allChains {
            let grey = chain.render(r: Film.midGrey, g: Film.midGrey, b: Film.midGrey)
            let r = FilmModel.sRGB(fromLinear: grey.r)
            let g = FilmModel.sRGB(fromLinear: grey.g)
            let b = FilmModel.sRGB(fromLinear: grey.b)
            #expect(abs(r - b) < 1.0 / 255 && abs(r - g) < 1.0 / 255, "\(label): \(r) \(g) \(b)")
        }
    }

    @Test func matteKeepsItsLiftedBlacks() {
        let matte = FilmChain(negative: Film.Negative.daylight200, print: Film.Print.matte, monochrome: false)
        let lab = FilmChain(negative: Film.Negative.daylight200, print: Film.Print.lab, monochrome: false)
        #expect(matte.render(r: 0, g: 0, b: 0).g > 2 * lab.render(r: 0, g: 0, b: 0).g)
    }

    // MARK: Cube

    private func lattice(_ data: Data, dimension: Int, r: Int, g: Int, b: Int) -> (Float, Float, Float) {
        data.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let index = ((b * dimension + g) * dimension + r) * 4
            return (floats[index], floats[index + 1], floats[index + 2])
        }
    }

    @Test func cubeHasTheSizeCoreImageExpects() {
        let n = Self.testDimension
        let data = FilmLUT.cube(negative: Film.Negative.daylight200, print: Film.Print.lab, monochrome: false, dimension: n)
        #expect(data.count == n * n * n * 4 * MemoryLayout<Float>.size)
    }

    @Test func cubeIsMonotonicAlongANeutralRampAndBlackStaysBelowWhite() {
        let n = Self.testDimension
        for (negativeName, negative) in Self.negatives {
            for (printName, print) in Self.prints {
                for monochrome in [false, true] {
                    let data = FilmLUT.cube(negative: negative, print: print, monochrome: monochrome, dimension: n)
                    let label = "\(negativeName) + \(printName), mono \(monochrome)"
                    var previous = lattice(data, dimension: n, r: 0, g: 0, b: 0)
                    for i in 1..<n {
                        let next = lattice(data, dimension: n, r: i, g: i, b: i)
                        #expect(next.0 >= previous.0 && next.1 >= previous.1 && next.2 >= previous.2, "\(label) at \(i)")
                        previous = next
                    }
                    let black = lattice(data, dimension: n, r: 0, g: 0, b: 0)
                    let white = lattice(data, dimension: n, r: n - 1, g: n - 1, b: n - 1)
                    #expect(black.0 < white.0 && black.1 < white.1 && black.2 < white.2, "\(label)")
                }
            }
        }
    }

    @Test func eachColourChannelIsMonotonicAlongItsOwnAxis() {
        let n = Self.testDimension
        let mid = n / 2
        let data = FilmLUT.cube(negative: Film.Negative.daylight200, print: Film.Print.lab, monochrome: false, dimension: n)
        // Non-strict: v4 F14's saturation matrix can clip a channel to zero
        // exposure at the far corner of the lattice (a strongly
        // complementary colour), where two steps then print the same black
        for i in 1..<n {
            #expect(lattice(data, dimension: n, r: i, g: mid, b: mid).0 >= lattice(data, dimension: n, r: i - 1, g: mid, b: mid).0)
            #expect(lattice(data, dimension: n, r: mid, g: i, b: mid).1 >= lattice(data, dimension: n, r: mid, g: i - 1, b: mid).1)
            #expect(lattice(data, dimension: n, r: mid, g: mid, b: i).2 >= lattice(data, dimension: n, r: mid, g: mid, b: i - 1).2)
        }
        #expect(lattice(data, dimension: n, r: n - 1, g: mid, b: mid).0 > lattice(data, dimension: n, r: 0, g: mid, b: mid).0)
        #expect(lattice(data, dimension: n, r: mid, g: mid, b: n - 1).2 > lattice(data, dimension: n, r: mid, g: mid, b: 0).2)
    }

    @Test func monochromeCubesAreNeutralAtEveryLatticePoint() {
        let n = Self.testDimension
        let cases: [(String, NegativeProfile, Bool)] = [
            ("mono400", Film.Negative.mono400, false),
            ("mono3200", Film.Negative.mono3200, false),
            // OPEN v4-7 path: a colour stock with the B&W toggle on
            ("daylight200 + B&W", Film.Negative.daylight200, true),
        ]
        for (name, negative, monochrome) in cases {
            for (printName, print) in Self.prints {
                let data = FilmLUT.cube(negative: negative, print: print, monochrome: monochrome, dimension: n)
                var allNeutral = true
                for b in 0..<n {
                    for g in 0..<n {
                        for r in 0..<n {
                            let value = lattice(data, dimension: n, r: r, g: g, b: b)
                            if value.0 != value.1 || value.1 != value.2 { allNeutral = false }
                        }
                    }
                }
                #expect(allNeutral, "\(name) + \(printName) has a non-neutral lattice point")
            }
        }
    }

    @Test func cubesAreDeterministicAndTheCacheReturnsTheSameBytes() {
        let n = Self.testDimension
        let first = FilmLUT.cube(negative: Film.Negative.cine500T, print: Film.Print.cinema, monochrome: false, dimension: n)
        let second = FilmLUT.cube(negative: Film.Negative.cine500T, print: Film.Print.cinema, monochrome: false, dimension: n)
        let cached = FilmLUT.cachedCube(negative: Film.Negative.cine500T, print: Film.Print.cinema, monochrome: false, dimension: n)
        let cachedAgain = FilmLUT.cachedCube(negative: Film.Negative.cine500T, print: Film.Print.cinema, monochrome: false, dimension: n)

        #expect(first == second)
        #expect(cached == first)
        #expect(cachedAgain == first)
    }

    @Test func spectralWeightSetsSumToOne() {
        // Otherwise a neutral grey would change brightness in monochrome
        let sets = [Film.Spectral.panchromatic, Film.Spectral.extendedRed, Film.colourStockMonoWeights]
        for weights in sets {
            #expect(abs(weights.r + weights.g + weights.b - 1) < 1e-9)
        }
    }

    // docs/film-simulation.md §8.2: rows sum to one, so a neutral is untouched
    // (added by the test consolidation: this invariant had no direct test)
    @Test(arguments: negatives.map(\.0))
    func colourMatrixRowsSumToOne(stock name: String) throws {
        let negative = try #require(Self.negatives.first { $0.0 == name }?.1)
        let m = negative.colour
        for (row, sum) in [("r", m.rr + m.rg + m.rb), ("g", m.gr + m.gg + m.gb), ("b", m.br + m.bg + m.bb)] {
            #expect(abs(sum - 1) < 1e-9, "\(name) row \(row) sums to \(sum)")
        }
    }

    @Test func sRGBTransferRoundTrips() {
        for step in 0...20 {
            let value = Double(step) / 20
            #expect(abs(FilmModel.sRGB(fromLinear: FilmModel.linear(fromSRGB: value)) - value) < 1e-9)
        }
    }
}
