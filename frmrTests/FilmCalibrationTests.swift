import Foundation
import Testing
import UIKit
@testable import frmr

// v4 F14: measurable proxies for the stock calibration against real-film
// references (research/v4-film-reference-calibration.md §1). They pin the
// direction of each change, not exact colours.
struct FilmCalibrationTests {

    private typealias Film = Constants.ImageProcessing.Film

    private static func chain(_ stock: StripCustomization.FilmStock) -> FilmChain {
        FilmChain(negative: stock.negative!, print: stock.defaultPrint!.profile, monochrome: false)
    }

    private static func encoded(_ c: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
        (FilmModel.sRGB(fromLinear: c.r), FilmModel.sRGB(fromLinear: c.g), FilmModel.sRGB(fromLinear: c.b))
    }

    /// Red minus blue, sRGB, for a neutral linear input.
    private static func warmth(_ stock: StripCustomization.FilmStock, at input: Double) -> Double {
        let out = encoded(chain(stock).render(r: input, g: input, b: input))
        return out.r - out.b
    }

    private static func hueAndSaturation(_ c: (r: Double, g: Double, b: Double)) -> (hue: Double, saturation: Double) {
        let maximum = max(c.r, c.g, c.b)
        let minimum = min(c.r, c.g, c.b)
        let delta = maximum - minimum
        guard delta > 1e-9, maximum > 0 else { return (0, 0) }
        var hue: Double
        if maximum == c.r {
            hue = 60 * ((c.g - c.b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == c.g {
            hue = 60 * ((c.b - c.r) / delta + 2)
        } else {
            hue = 60 * ((c.r - c.g) / delta + 4)
        }
        return (hue < 0 ? hue + 360 : hue, delta / maximum)
    }

    @Test func daylightIsWarmerThanPortraitAtMidAndHighlight() {
        for input in [0.35, 0.8] {
            let daylight = Self.warmth(.daylight200, at: input)
            let portrait = Self.warmth(.portrait400, at: input)
            #expect(daylight > portrait + 4.0 / 255, "at \(input): Daylight \(daylight * 255), Portrait \(portrait * 255)")
            #expect(daylight > 0, "Daylight reads warm at \(input)")
        }
    }

    /// Slope of log output against log input across the quarter tones to
    /// the upper mids, on the neutral response.
    private static func effectiveGamma(_ stock: StripCustomization.FilmStock) -> Double {
        let chain = chain(stock)
        func luminance(_ x: Double) -> Double {
            let out = chain.render(r: x, g: x, b: x)
            return Film.Spectral.panchromatic.luminance(r: out.r, g: out.g, b: out.b)
        }
        return (log10(luminance(0.36)) - log10(luminance(0.09))) / (log10(0.36) - log10(0.09))
    }

    @Test func portraitIsSofterThanDaylight() {
        #expect(Self.effectiveGamma(.portrait400) < Self.effectiveGamma(.daylight200) - 0.1)
    }

    @Test func cineShadowsLeanTealNotBlue() {
        let chain = Self.chain(.cine500T)
        for input in [0.0, 0.005, 0.02] {
            let shadow = Self.hueAndSaturation(Self.encoded(chain.render(r: input, g: input, b: input)))
            #expect(shadow.saturation > 0.05, "a visible cast at \(input)")
            #expect((165...200).contains(shadow.hue), "Cine 500T shadow hue \(shadow.hue)° at \(input)")
        }
    }

    @Test func slideIsTheMostSaturatedStock() {
        let patches: [(Double, Double, Double)] = [
            (0.60, 0.15, 0.10), (0.70, 0.35, 0.08), (0.15, 0.45, 0.12), (0.10, 0.20, 0.55), (0.45, 0.30, 0.25),
        ]
        func saturation(_ stock: StripCustomization.FilmStock) -> Double {
            let chain = Self.chain(stock)
            return patches.map {
                Self.hueAndSaturation(Self.encoded(chain.render(r: $0.0, g: $0.1, b: $0.2))).saturation
            }.reduce(0, +) / Double(patches.count)
        }
        let slide = saturation(.slide100)
        for stock in [StripCustomization.FilmStock.daylight200, .portrait400, .cine500T] {
            #expect(slide >= saturation(stock), "Slide \(slide) vs \(stock.label) \(saturation(stock))")
        }
        for stock in [StripCustomization.FilmStock.daylight200, .cine500T, .slide100] {
            #expect(saturation(.portrait400) < saturation(stock), "Portrait is the restrained one, vs \(stock.label)")
        }
    }

    // User review: Portrait 400 skies read lavender. A sky blue must not
    // move toward purple (a higher hue) compared with the untouched photo.
    @Test func portraitSkiesStayCyanNotLavender() {
        let chain = Self.chain(.portrait400)
        let skies: [(Double, Double, Double)] = [(0.20, 0.35, 0.60), (0.12, 0.22, 0.50), (0.05, 0.12, 0.45), (0.30, 0.45, 0.70)]
        for sky in skies {
            let off = Self.hueAndSaturation(Self.encoded((sky.0, sky.1, sky.2))).hue
            let portrait = Self.hueAndSaturation(Self.encoded(chain.render(r: sky.0, g: sky.1, b: sky.2))).hue
            #expect(portrait <= off, "sky \(sky): Portrait \(portrait)° vs Off \(off)°")
        }
    }

    @Test func mono3200GrainBacksOffInHighlights() throws {
        func variance(_ grey: CGFloat) throws -> Double {
            let size = CGSize(width: 96, height: 96)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let patch = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(white: grey, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            var customization = StripCustomization.stockDefaults(for: .mono3200)
            customization.effects = .init(halation: false, bloom: false, lightLeak: false)
            let output = ImageProcessor.applyStripLook(to: patch, customization: customization, outputWidth: 96, seed: 5)
            let cgImage = try #require(output.cgImage)
            var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
            let context = try #require(CGContext(
                data: &bytes, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 96, height: 96))
            let values = stride(from: 0, to: bytes.count, by: 4).map { Double(bytes[$0]) }
            let mean = values.reduce(0, +) / Double(values.count)
            return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        }
        let highlight = try variance(0.85)
        let midtone = try variance(0.46)
        #expect(highlight < midtone, "highlight grain variance \(highlight) vs midtone \(midtone)")
        #expect(Constants.ImageProcessing.Film.Grain.mono3200.coarseWeight
            < Constants.ImageProcessing.Film.Grain.standard.coarseWeight)
    }
}


// MARK: - Stock swatches (v5.2 S8)

struct FilmSwatchTests {

    @Test(arguments: StripCustomization.FilmStock.allCases)
    func everyStockHasTwoOrThreeDeterministicColours(stock: StripCustomization.FilmStock) {
        let first = FilmSwatch.rgbValues(for: stock)
        #expect((2...3).contains(first.count))
        #expect(FilmSwatch.colors(for: stock).count == first.count)
        let second = FilmSwatch.rgbValues(for: stock)
        #expect(zip(first, second).allSatisfy { $0.r == $1.r && $0.g == $1.g && $0.b == $1.b })
        #expect(first.allSatisfy { (0...1).contains($0.r) && (0...1).contains($0.g) && (0...1).contains($0.b) })
    }

    @Test func monochromeStocksAreGreyAndColourStocksDifferFromEachOtherAndFromOff() {
        for stock in [StripCustomization.FilmStock.mono400, .mono3200] {
            #expect(FilmSwatch.rgbValues(for: stock).allSatisfy { abs($0.r - $0.g) < 0.02 && abs($0.g - $0.b) < 0.02 }, "\(stock.label)")
        }
        let off = FilmSwatch.rgbValues(for: .none)
        let cine = FilmSwatch.rgbValues(for: .cine500T)
        let daylight = FilmSwatch.rgbValues(for: .daylight200)
        #expect(zip(off, cine).contains { abs($0.r - $1.r) > 0.01 || abs($0.b - $1.b) > 0.01 })
        #expect(zip(cine, daylight).contains { abs($0.r - $1.r) > 0.01 || abs($0.b - $1.b) > 0.01 })
    }
}
