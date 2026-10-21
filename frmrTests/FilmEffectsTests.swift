import CoreImage
import Foundation
import Testing
import UIKit
@testable import frmr

// v4 F4–F6: the physical effects. Isolated effects are rendered through a
// local float context like the strip's; pipeline tests go through
// applyStripLook.

private let floatContext = CIContext(options: [.workingFormat: CIFormat.RGBAh])
private let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

private struct Pixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CIImage) {
        guard let cgImage = floatContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else {
            return nil
        }
        self.init(cgImage)
    }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage)
    }

    init?(_ cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = raw
    }

    func rgb(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]))
    }

    /// Mean of each channel over the pixels whose Chebyshev distance from
    /// the centre lies in `band` (a square ring around a centred dot).
    func ringMean(band: ClosedRange<Int>) -> (r: Double, g: Double, b: Double) {
        var total = (r: 0.0, g: 0.0, b: 0.0)
        var count = 0.0
        let cx = width / 2, cy = height / 2
        for y in 0..<height {
            for x in 0..<width where band.contains(max(abs(x - cx), abs(y - cy))) {
                let p = rgb(x, y)
                total.r += p.r; total.g += p.g; total.b += p.b
                count += 1
            }
        }
        return (total.r / count, total.g / count, total.b / count)
    }
}

private let side: CGFloat = 64

/// Black square with a white dot `dot` pixels wide in the middle.
private func dotImage(dot: CGFloat = 4) -> CIImage {
    let extent = CGRect(x: 0, y: 0, width: side, height: side)
    let black = CIImage(color: .black).cropped(to: extent)
    let white = CIImage(color: .white).cropped(to: CGRect(
        x: (side - dot) / 2, y: (side - dot) / 2, width: dot, height: dot
    ))
    return white.composited(over: black)
}

private func uiImage(_ image: CIImage) -> UIImage? {
    guard let cgImage = floatContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: sRGB) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

// MARK: - F4 Halation

struct HalationTests {

    // Wide output so the glow radius spans a few pixels of the 64 px test image
    private let outputWidth: CGFloat = 400

    @Test func aWhiteDotGainsARedRing() throws {
        let halated = try #require(Pixels(ImageProcessor.applyHalation(to: dotImage(), strength: 1, outputWidth: outputWidth)))
        let plain = try #require(Pixels(dotImage()))
        // The dot covers Chebyshev distance 0…2; the ring sits just outside it
        let ring = halated.ringMean(band: 4...7)
        let before = plain.ringMean(band: 4...7)

        #expect(before.r == 0, "the ring starts black")
        #expect(ring.r > before.r + 1, "the ring gains red energy")
        #expect(ring.r > ring.b, "the glow is red-dominant")
    }

    @Test func zeroStrengthIsPixelIdentical() throws {
        let input = dotImage()
        let output = ImageProcessor.applyHalation(to: input, strength: 0, outputWidth: outputWidth)
        #expect(try #require(Pixels(output)) == (try #require(Pixels(input))))
    }

    @Test func nothingAboveTheThresholdAddsNothing() throws {
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        let mid = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: extent)
        let output = ImageProcessor.applyHalation(to: mid, strength: 1, outputWidth: outputWidth)
        #expect(try #require(Pixels(output)) == (try #require(Pixels(mid))))
    }

    @Test func halationToggleOnlyChangesTheStripWhenThereAreHighlights() throws {
        let dot = try #require(uiImage(dotImage()))
        var on = StripCustomization()
        on.filmStock = .cine500T
        on.effects.halation = true
        var off = on
        off.effects.halation = false

        let withGlow = try #require(Pixels(ImageProcessor.applyStripLook(to: dot, customization: on, outputWidth: side)))
        let without = try #require(Pixels(ImageProcessor.applyStripLook(to: dot, customization: off, outputWidth: side)))
        #expect(withGlow.ringMean(band: 3...6).r > without.ringMean(band: 3...6).r)

        let dark = try #require(uiImage(CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))))
        let darkOn = try #require(Pixels(ImageProcessor.applyStripLook(to: dark, customization: on, outputWidth: side)))
        let darkOff = try #require(Pixels(ImageProcessor.applyStripLook(to: dark, customization: off, outputWidth: side)))
        // Not bit-exact: the halation branch makes Core Image store the
        // pre-cube image in a half-float buffer, and the cube can turn that
        // rounding into one 8-bit step. The glow itself adds exactly zero
        // (nothingAboveTheThresholdAddsNothing).
        let largestStep = zip(darkOn.bytes, darkOff.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(largestStep <= 1)
    }

    @Test func cineHasTheStrongestHalation() {
        let others = StripCustomization.FilmStock.allCases.filter { $0 != .cine500T }
        #expect(others.allSatisfy { $0.halationStrength < StripCustomization.FilmStock.cine500T.halationStrength })
        #expect(StripCustomization.FilmStock.none.halationStrength == 0)
    }
}

// MARK: - F5 Grain v2

struct GrainTests {

    private typealias Film = Constants.ImageProcessing.Film

    /// A flat patch of the given linear value.
    private func flat(_ value: CGFloat, size: CGFloat = 128) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let color = CIColor(red: value, green: value, blue: value, alpha: 1, colorSpace: linear)
            ?? CIColor(red: value, green: value, blue: value)
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func stats(_ pixels: Pixels) -> (mean: Double, variance: Double) {
        var values: [Double] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgb(x, y)
                values.append(0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return (mean, values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count))
    }

    /// Variance of print density (−log10 of linear luminance): the quantity
    /// the density curve shapes.
    private func densityVariance(_ pixels: Pixels) -> Double {
        var values: [Double] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let p = pixels.rgb(x, y)
                let encoded = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) / 255
                values.append(-log10(max(FilmModel.linear(fromSRGB: encoded), 1e-5)))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    private func grained(_ input: CIImage, iso: Int, monochrome: Bool = false, seed: UInt64 = 1) throws -> Pixels {
        try #require(Pixels(ImageProcessor.addGrain(
            to: input,
            intensity: FilmGrain.intensity(forISO: iso),
            sizePixels: FilmGrain.sizePixels(forISO: iso),
            monochrome: monochrome,
            seed: seed
        )))
    }

    @Test func grainVarianceIncreasesWithISO() throws {
        let grey = flat(0.214)   // linear value of sRGB 0.5
        let variances = try [100, 200, 400, 3200].map { try stats(grained(grey, iso: $0)).variance }
        for (lower, higher) in zip(variances, variances.dropFirst()) {
            #expect(higher > lower, "variances \(variances)")
        }
    }

    @Test func grainKeepsTheMeanOfAMidGreyPatch() throws {
        let grey = flat(0.214, size: 256)
        let plain = stats(try #require(Pixels(grey))).mean
        for iso in [100, 200, 400, 500, 3200] {
            for monochrome in [false, true] {
                let mean = stats(try grained(grey, iso: iso, monochrome: monochrome)).mean
                #expect(abs(mean - plain) < 1, "ISO \(iso), mono \(monochrome): mean \(mean) vs \(plain)")
            }
        }
    }

    @Test func sameSeedIsIdenticalAndDifferentSeedsDiffer() throws {
        let grey = flat(0.214)
        let first = try grained(grey, iso: 400, seed: 7)
        let again = try grained(grey, iso: 400, seed: 7)
        let other = try grained(grey, iso: 400, seed: 8)
        #expect(first == again)
        #expect(first != other)
    }

    @Test func stripSeedsAreStablePerSlotAndDistinctAcrossSlots() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let seeds = (0..<Constants.entriesPerStrip).map { StripGenerator.seed(for: date, slot: $0) }
        #expect(Set(seeds).count == seeds.count)
        #expect(seeds == (0..<Constants.entriesPerStrip).map { StripGenerator.seed(for: date, slot: $0) })
        #expect(StripGenerator.seed(for: date.addingTimeInterval(86_400), slot: 0) != seeds[0])
    }

    // OBS-V4-5: strips rendered together must not repeat each other's grain
    @Test func framesAcrossStripsGetDistinctSeedsAndStripZeroIsUnchanged() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let perStrip = Constants.entriesPerStrip
        let seeds = (0..<2).flatMap { strip in
            (0..<perStrip).map { StripGenerator.seed(for: date, slot: StripGenerator.frameIndex(strip: strip, slot: $0)) }
        }
        #expect(Set(seeds).count == seeds.count)
        // Strip 0 keeps the single-strip seeds
        #expect(Array(seeds.prefix(perStrip)) == (0..<perStrip).map { StripGenerator.seed(for: date, slot: $0) })
    }

    @Test func secondStripDiffersFromFirstButEachIsDeterministic() throws {
        let photo = try #require(uiImage(flat(0.2)))
        let cells = (0..<Constants.entriesPerStrip).map { _ in StripGenerator.Cell(image: photo, caption: "") }
        var customization = StripCustomization()
        customization.filmStock = .mono3200
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        func render(_ strip: Int) throws -> Pixels {
            try #require(Pixels(StripGenerator.render(strip: cells, customization: customization, date: date, stripIndex: strip)))
        }
        let first = try render(0)
        let second = try render(1)
        #expect(first != second, "strip 2 must not repeat strip 1's grain")
        #expect(try render(0) == first)
        #expect(try render(1) == second)
        // Default stripIndex is the single-strip render
        #expect(try #require(Pixels(StripGenerator.render(strip: cells, customization: customization, date: date))) == first)
    }

    @Test func stripLookIsSeededThroughApplyStripLook() throws {
        let photo = try #require(uiImage(flat(0.3)))
        var customization = StripCustomization()
        customization.filmStock = .portrait400
        let a = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: customization, outputWidth: 64, seed: 3)))
        let b = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: customization, outputWidth: 64, seed: 3)))
        let c = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: customization, outputWidth: 64, seed: 4)))
        #expect(a == b)
        #expect(a != c)
    }

    @Test func monochromeGrainIsNeutral() throws {
        let pixels = try grained(flat(0.214), iso: 3200, monochrome: true)
        for y in stride(from: 0, to: pixels.height, by: 7) {
            for x in stride(from: 0, to: pixels.width, by: 7) {
                let p = pixels.rgb(x, y)
                #expect(p.r == p.g && p.g == p.b)
            }
        }
    }

    @Test func colourGrainHasSomeChroma() throws {
        let pixels = try grained(flat(0.214), iso: 3200, monochrome: false)
        var differs = false
        for y in 0..<pixels.height where !differs {
            for x in 0..<pixels.width where pixels.rgb(x, y).r != pixels.rgb(x, y).b {
                differs = true
                break
            }
        }
        #expect(differs)
    }

    // Density variance per patch follows the curve: shadows (weight 1.0) >
    // highlights (0.8) > midtones (0.3) with the default U.
    @Test func varianceIsLargestWhereTheDensityCurveIsHighest() throws {
        func patch(atDensity d: Double) -> CIImage {
            flat(CGFloat(pow(10, -d * Film.grainDensityRange)))
        }
        let highlight = densityVariance(try grained(patch(atDensity: 0.08), iso: 3200))
        let midtone = densityVariance(try grained(patch(atDensity: 0.5), iso: 3200))
        let shadow = densityVariance(try grained(patch(atDensity: 0.8), iso: 3200))
        #expect(midtone < highlight && midtone < shadow, "h \(highlight) m \(midtone) s \(shadow)")
    }

    @Test func amplitudeTableFollowsTheDensityCurve() {
        let curve = Film.grainDensityCurve
        #expect(FilmGrain.weight(atDensity: 0) == curve[0])
        #expect(FilmGrain.weight(atDensity: 1) == curve[curve.count - 1])
        #expect(abs(FilmGrain.weight(atDensity: 0.5) - curve[1]) < 1e-12)
        let table = FilmGrain.amplitudeTable()
        #expect(table.count == Film.grainAmplitudeTableSize)
        // White end reads the paper-white weight, black end the densest weight
        let white = FilmModel.linear(fromSRGB: Double(table[table.count - 1]))
        #expect(abs(white - curve[0]) < 1e-5)
    }

    @Test func isoTablesInterpolatePerStop() {
        #expect(FilmGrain.intensity(forISO: 100) == 0.04)
        #expect(FilmGrain.intensity(forISO: 3200) == 0.30)
        let i200 = FilmGrain.intensity(forISO: 200)
        #expect(i200 > 0.04 && i200 < 0.12)
        #expect(FilmGrain.sizePixels(forISO: 500) > FilmGrain.sizePixels(forISO: 400))
    }

    @Test func seededRandomIsReproducible() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        #expect((0..<8).map { _ in a.next() } == (0..<8).map { _ in b.next() })
        #expect(SeededRandom.derive(1, salt: 2) != SeededRandom.derive(1, salt: 3))
    }
}

// MARK: - F6 Bloom and light leak

struct BloomAndLightLeakTests {

    private let extent = CGRect(x: 0, y: 0, width: 64, height: 48)

    private var grey: CIImage {
        CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: extent)
    }

    private func neverDarker(_ output: Pixels, than input: Pixels) -> (never: Bool, someBrighter: Bool) {
        var never = true, brighter = false
        for (a, b) in zip(output.bytes, input.bytes) {
            if a < b { never = false }
            if a > b { brighter = true }
        }
        return (never, brighter)
    }

    @Test func lightLeakOnlyBrightensAndIsDeterministic() throws {
        let input = try #require(Pixels(grey))
        let leak = try #require(Pixels(ImageProcessor.applyLightLeak(to: grey, seed: 11)))
        let again = try #require(Pixels(ImageProcessor.applyLightLeak(to: grey, seed: 11)))
        let result = neverDarker(leak, than: input)

        #expect(leak == again)
        #expect(result.never, "a leak must never darken a pixel")
        #expect(result.someBrighter, "a leak must brighten something")
    }

    @Test func lightLeakIsWarm() throws {
        let leak = try #require(Pixels(ImageProcessor.applyLightLeak(to: grey, seed: 11)))
        var warm = false
        for y in 0..<leak.height {
            for x in 0..<leak.width {
                let p = leak.rgb(x, y)
                if p.r > p.b + 10 { warm = true }
            }
        }
        #expect(warm)
    }

    @Test func leakPlacementIsSeededAndLiesOutsideTheFrame() {
        let a = LightLeak.spots(seed: 1, width: 100, height: 80)
        #expect(a == LightLeak.spots(seed: 1, width: 100, height: 80))
        let placements = Set((0..<16).map { LightLeak.spots(seed: UInt64($0), width: 100, height: 80).first?.centreX ?? 0 })
        #expect(placements.count > 1, "different seeds should move the leak")
        for seed in 0..<32 {
            guard let first = LightLeak.spots(seed: UInt64(seed), width: 100, height: 80).first else {
                Issue.record("no spot"); continue
            }
            let outside = first.centreX < 0 || first.centreX > 100 || first.centreY < 0 || first.centreY > 80
            #expect(outside, "seed \(seed) centre should sit just outside an edge")
        }
    }

    @Test func bloomSpreadsHighlightsAndNeverDarkens() throws {
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 28, y: 20, width: 8, height: 8))
            .composited(over: CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: extent))
        let input = try #require(Pixels(dot))
        let bloomed = try #require(Pixels(ImageProcessor.applyBloom(to: dot, outputWidth: 260)))
        let result = neverDarker(bloomed, than: input)

        #expect(result.never)
        // Just outside the dot picks up glow
        #expect(bloomed.rgb(32, 48 - 1 - 30).r > input.rgb(32, 48 - 1 - 30).r)
    }

    @Test func disabledEffectsArePixelIdenticalToTheOffPath() throws {
        let photo = try #require(uiImage(grey))
        var base = StripCustomization()
        base.filmStock = .daylight200
        base.effects = .init(halation: true, bloom: false, lightLeak: false)
        var leakOnly = base
        leakOnly.effects.lightLeak = true

        let off = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: base, outputWidth: 64, seed: 5)))
        let offAgain = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: base, outputWidth: 64, seed: 5)))
        let leak = try #require(Pixels(ImageProcessor.applyStripLook(to: photo, customization: leakOnly, outputWidth: 64, seed: 5)))

        #expect(off == offAgain)
        #expect(leak != off, "turning the leak on must change the strip")
    }

    @Test func effectsAreOffByDefault() {
        #expect(!StripCustomization.FilmEffects.stockDefaults.bloom)
        #expect(!StripCustomization.FilmEffects.stockDefaults.lightLeak)
    }
}
