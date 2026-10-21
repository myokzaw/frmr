import Foundation
import Testing
import UIKit
@testable import frmr

// QA-owned v4 regressions (spec §New files, §Definition of done):
//  - orientation: no photo is ever rotated relative to its unfiltered render,
//    for every stock × B&W × effect combination (the F0 bug class)
//  - determinism: the same strip re-renders pixel-identically
//  - the Off fast path hands back the caller's own image
//  - bloom and light leak never darken a full strip
//
// Orientation oracle: UIKit itself. Drawing a tagged UIImage into an `.up`
// renderer resolves the tag the way every other screen in the app shows the
// photo, so "the strip look of the tagged photo" must equal "the strip look
// of UIKit's upright copy". Images are tiny so the whole matrix stays fast.

// MARK: - Helpers

/// RGBA8 sRGB pixels of a rendered image, top row first.
private struct RegressionPixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
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

    /// Mean colour of a band of rows.
    func meanRows(_ rows: Range<Int>) -> (r: Double, g: Double, b: Double) {
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for y in rows {
            for x in 0..<width {
                let p = rgb(x, y)
                sum = (sum.r + p.r, sum.g + p.g, sum.b + p.b)
            }
        }
        let n = Double(rows.count * width)
        return (sum.r / n, sum.g / n, sum.b / n)
    }

    /// Largest per-channel difference, or nil when the sizes differ.
    func maxDifference(to other: RegressionPixels) -> Int? {
        guard width == other.width, height == other.height else { return nil }
        var worst = 0
        for index in bytes.indices where index % 4 != 3 {
            worst = max(worst, abs(Int(bytes[index]) - Int(other.bytes[index])))
        }
        return worst
    }

    /// Mean per-channel absolute difference, or nil when the sizes differ.
    func meanDifference(to other: RegressionPixels) -> Double? {
        guard width == other.width, height == other.height else { return nil }
        var total = 0
        for index in bytes.indices where index % 4 != 3 {
            total += abs(Int(bytes[index]) - Int(other.bytes[index]))
        }
        return Double(total) / Double(width * height * 3)
    }

    /// Largest amount by which any channel of `self` is darker than `other`.
    func maxDarkening(comparedTo other: RegressionPixels) -> Int? {
        guard width == other.width, height == other.height else { return nil }
        var worst = 0
        for index in bytes.indices where index % 4 != 3 {
            worst = max(worst, Int(other.bytes[index]) - Int(bytes[index]))
        }
        return worst
    }
}

private enum Fixture {
    typealias Stock = StripCustomization.FilmStock
    typealias Effects = StripCustomization.FilmEffects

    /// Slot width for the matrix: small, but large enough that the 2×
    /// downscale and every blur radius actually do something.
    static let slotWidth: CGFloat = 32
    static let seed = StripGenerator.seed(for: Date(timeIntervalSince1970: 1_790_000_000), slot: 1)
    static let stripDate = Date(timeIntervalSince1970: 1_790_000_000)

    /// Sensor-space pixels as the phone stores them: 128×64, red on the
    /// left half, blue on the right. Tagged `.right` the red edge is the
    /// top of the photo; tagged `.left` it is the bottom.
    static let sensor: CGImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 64, y: 0, width: 64, height: 64))
        }
        return image.cgImage
    }()

    /// A gradient-and-highlights photo for full-strip tests, so halation,
    /// bloom and grain all have something to act on.
    static let scene: CGImage? = {
        let size = CGSize(width: 96, height: 72)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.85, green: 0.6, blue: 0.35, alpha: 1).cgColor,
                          UIColor(red: 0.05, green: 0.12, blue: 0.3, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []
                )
            }
            UIColor.white.setFill()
            context.fill(CGRect(x: 40, y: 30, width: 8, height: 8))
            UIColor.black.setFill()
            context.fill(CGRect(x: 10, y: 50, width: 14, height: 14))
        }
        return image.cgImage
    }()

    static func tagged(_ cgImage: CGImage, _ orientation: UIImage.Orientation) -> UIImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    /// UIKit's own upright rendering of a tagged photo, as an `.up` image.
    static func uprightCopy(of image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
        guard let cgImage = drawn.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// All eight on/off combinations of halation, bloom and light leak.
    static let allEffects: [Effects] = [false, true].flatMap { halation in
        [false, true].flatMap { bloom in
            [false, true].map { leak in Effects(halation: halation, bloom: bloom, lightLeak: leak) }
        }
    }

    static func customization(_ stock: Stock, blackAndWhite: Bool, effects: Effects) -> StripCustomization {
        var customization = StripCustomization()
        customization.filmStock = stock
        customization.blackAndWhite = blackAndWhite
        customization.effects = effects
        return customization
    }

    static func describe(_ c: StripCustomization) -> String {
        "\(StripCustomization.label(forStockChoice: c.filmStock)) B&W:\(c.blackAndWhite) halation:\(c.effects.halation) "
            + "bloom:\(c.effects.bloom) leak:\(c.effects.lightLeak)"
    }

    static func strip(_ photo: UIImage, customization: StripCustomization) -> UIImage {
        let cells = (0..<Constants.entriesPerStrip).map { StripGenerator.Cell(image: photo, caption: "frame \($0)") }
        return StripGenerator.render(strip: cells, customization: customization, date: stripDate)
    }
}

// MARK: - Orientation

struct StripLookOrientationRegressionTests {

    /// The tagged photo through the strip look must equal UIKit's upright
    /// copy through the same look, for every B&W × effect combination.
    private func assertMatchesUprightOracle(
        stock: StripCustomization.FilmStock,
        orientation: UIImage.Orientation,
        effects: [StripCustomization.FilmEffects]
    ) throws {
        let sensor = try #require(Fixture.sensor)
        let tagged = Fixture.tagged(sensor, orientation)
        let upright = try #require(Fixture.uprightCopy(of: tagged))

        for blackAndWhite in [false, true] {
            for effect in effects {
                let customization = Fixture.customization(stock, blackAndWhite: blackAndWhite, effects: effect)
                let label = "\(Fixture.describe(customization)) orientation:\(orientation.rawValue)"
                let output = ImageProcessor.applyStripLook(
                    to: tagged, customization: customization, outputWidth: Fixture.slotWidth, seed: Fixture.seed
                )
                let reference = ImageProcessor.applyStripLook(
                    to: upright, customization: customization, outputWidth: Fixture.slotWidth, seed: Fixture.seed
                )

                if stock == .none && !blackAndWhite {
                    // Fast path: the caller's image comes back and the strip
                    // aspect-fills it, honouring the tag (covered below)
                    #expect(output === tagged, "\(label): Off must return the original")
                    continue
                }
                #expect(output.imageOrientation == .up, "\(label): filtered output must be baked upright")
                let out = try #require(RegressionPixels(output))
                // The slot-sized centre crop, whatever the tag (was the single-case
                // stripLookKeepsATaggedPhotoUpright)
                #expect(out.width == Int(Fixture.slotWidth)
                        && out.height == Int((Fixture.slotWidth / Constants.Strip.cellAspectRatio).rounded()),
                        "\(label): output must be the slot size, got \(out.width)×\(out.height)")
                let ref = try #require(RegressionPixels(reference))
                let difference = out.maxDifference(to: ref)
                #expect(difference != nil, "\(label): size \(out.width)×\(out.height) vs \(ref.width)×\(ref.height)")
                if let difference {
                    #expect(difference <= 2, "\(label): differs from the upright render by \(difference)/255")
                }
            }
        }
    }

    @Test("Tagged .right matches its upright render", arguments: StripCustomization.FilmStock.allCases)
    func rightTaggedMatchesUpright(stock: StripCustomization.FilmStock) throws {
        try assertMatchesUprightOracle(stock: stock, orientation: .right, effects: Fixture.allEffects)
    }

    @Test("Tagged .left matches its upright render", arguments: StripCustomization.FilmStock.allCases)
    func leftTaggedMatchesUpright(stock: StripCustomization.FilmStock) throws {
        try assertMatchesUprightOracle(stock: stock, orientation: .left, effects: Fixture.allEffects)
    }

    @Test("Every EXIF orientation matches its upright render", arguments: StripCustomization.FilmStock.allCases)
    func everyOrientationMatchesUpright(stock: StripCustomization.FilmStock) throws {
        let allOn = StripCustomization.FilmEffects(halation: true, bloom: true, lightLeak: true)
        let orientations: [UIImage.Orientation] = [
            .up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored,
        ]
        for orientation in orientations {
            try assertMatchesUprightOracle(stock: stock, orientation: orientation, effects: [allOn])
        }
    }

    /// Absolute check, independent of the oracle: the red edge is on top for
    /// `.right` and at the bottom for `.left`. Colour renders compare red
    /// against blue; monochrome renders compare brightness, since red is
    /// lighter than blue under every stock's spectral weights.
    @Test("Red edge lands on the correct side", arguments: StripCustomization.FilmStock.allCases)
    func redEdgeLandsOnTheCorrectSide(stock: StripCustomization.FilmStock) throws {
        let sensor = try #require(Fixture.sensor)
        for (orientation, redOnTop) in [(UIImage.Orientation.right, true), (.left, false)] {
            for blackAndWhite in [false, true] {
                for effect in Fixture.allEffects where !effect.lightLeak {
                    // Light leak is excluded here: it can legitimately brighten
                    // one edge more than the other. The oracle tests cover it.
                    let customization = Fixture.customization(stock, blackAndWhite: blackAndWhite, effects: effect)
                    let label = "\(Fixture.describe(customization)) orientation:\(orientation.rawValue)"
                    let output = ImageProcessor.applyStripLook(
                        to: Fixture.tagged(sensor, orientation), customization: customization,
                        outputWidth: Fixture.slotWidth, seed: Fixture.seed
                    )
                    // The Off fast path returns the tagged original; resolve
                    // it the way the strip draws it
                    let upright = try #require(Fixture.uprightCopy(of: output))
                    let pixels = try #require(RegressionPixels(upright))
                    let band = pixels.height / 4
                    let top = pixels.meanRows(0..<band)
                    let bottom = pixels.meanRows((pixels.height - band)..<pixels.height)
                    let (red, blue) = redOnTop ? (top, bottom) : (bottom, top)

                    if customization.rendersInBlackAndWhite {
                        let lumRed = 0.2126 * red.r + 0.7152 * red.g + 0.0722 * red.b
                        let lumBlue = 0.2126 * blue.r + 0.7152 * blue.g + 0.0722 * blue.b
                        #expect(lumRed > lumBlue + 4, "\(label): red half should be the lighter one (\(lumRed) vs \(lumBlue))")
                    } else {
                        #expect(red.r - red.b > 40, "\(label): red edge on the wrong side")
                        #expect(blue.b - blue.r > 40, "\(label): blue edge on the wrong side")
                    }
                }
            }
        }
    }

    /// End to end through StripGenerator: a strip of `.right`-tagged photos
    /// must equal a strip of their upright copies, filtered or not.
    @Test("Full strip of tagged photos matches the upright strip",
          arguments: [StripCustomization.FilmStock.none, .daylight200, .cine500T, .slide100, .mono3200])
    func fullStripMatchesUprightStrip(stock: StripCustomization.FilmStock) throws {
        let scene = try #require(Fixture.scene)
        let tagged = Fixture.tagged(scene, .right)
        let upright = try #require(Fixture.uprightCopy(of: tagged))
        for blackAndWhite in [false, true] {
            let customization = Fixture.customization(
                stock, blackAndWhite: blackAndWhite,
                effects: .init(halation: true, bloom: true, lightLeak: true)
            )
            let a = try #require(RegressionPixels(Fixture.strip(tagged, customization: customization)))
            let b = try #require(RegressionPixels(Fixture.strip(upright, customization: customization)))
            if stock == .none && !blackAndWhite {
                // Unfiltered fast path: UIKit draws the tagged photo rotated
                // and scaled in one step, which resamples edges differently
                // from drawing a pre-rotated copy (checked by eye: both are
                // upright, edges shift by about a pixel). Compare the mean.
                let mean = try #require(a.meanDifference(to: b))
                #expect(mean < 1.0, "\(Fixture.describe(customization)): strip differs from upright, mean \(mean)/255")
            } else {
                let difference = try #require(a.maxDifference(to: b))
                #expect(difference <= 2, "\(Fixture.describe(customization)): strip differs from upright by \(difference)/255")
            }
        }
    }
}

// MARK: - Determinism and the Off fast path

struct StripLookDeterminismRegressionTests {

    @Test("Same seed renders pixel-identically, another seed does not",
          arguments: StripCustomization.FilmStock.allCases)
    func sameSeedIsPixelIdentical(stock: StripCustomization.FilmStock) throws {
        let scene = try #require(Fixture.scene)
        let photo = Fixture.tagged(scene, .right)
        for blackAndWhite in [false, true] {
            let customization = Fixture.customization(
                stock, blackAndWhite: blackAndWhite, effects: .init(halation: true, bloom: true, lightLeak: true)
            )
            let first = ImageProcessor.applyStripLook(
                to: photo, customization: customization, outputWidth: 48, seed: Fixture.seed
            )
            let second = ImageProcessor.applyStripLook(
                to: photo, customization: customization, outputWidth: 48, seed: Fixture.seed
            )
            #expect(RegressionPixels(first) == RegressionPixels(second), "\(Fixture.describe(customization))")
            if stock != .none {
                // Grain and the light leak are seeded (Off has neither, B&W or not): a different seed is a different frame
                let other = ImageProcessor.applyStripLook(
                    to: photo, customization: customization, outputWidth: 48, seed: Fixture.seed &+ 1
                )
                #expect(RegressionPixels(first) != RegressionPixels(other), "\(Fixture.describe(customization)): seed ignored")
            }
        }
    }

    @Test("StripGenerator.render twice for the same date gives identical PNG data",
          arguments: StripCustomization.FilmStock.allCases)
    func stripRenderIsByteIdentical(stock: StripCustomization.FilmStock) throws {
        let scene = try #require(Fixture.scene)
        let photo = Fixture.tagged(scene, .right)
        let customization = Fixture.customization(
            stock, blackAndWhite: false, effects: .init(halation: true, bloom: true, lightLeak: true)
        )
        let first = try #require(Fixture.strip(photo, customization: customization).pngData())
        let second = try #require(Fixture.strip(photo, customization: customization).pngData())
        #expect(first == second, "\(Fixture.describe(customization)): re-render is not byte-identical")
    }

    @Test("Off with B&W off returns the original instance for any effects or print")
    func offFastPathReturnsTheOriginal() throws {
        let sensor = try #require(Fixture.sensor)
        for orientation in [UIImage.Orientation.up, .right, .left] {
            let photo = Fixture.tagged(sensor, orientation)
            for effect in Fixture.allEffects {
                let prints: [StripCustomization.PrintStock?] = [nil] + StripCustomization.PrintStock.allCases.map { $0 }
                for print in prints {
                    var customization = Fixture.customization(.none, blackAndWhite: false, effects: effect)
                    customization.printStock = print
                    let output = ImageProcessor.applyStripLook(
                        to: photo, customization: customization, outputWidth: Fixture.slotWidth, seed: Fixture.seed
                    )
                    #expect(output === photo, "\(Fixture.describe(customization)) print:\(String(describing: print))")
                }
            }
        }
    }
}

// MARK: - Bloom and light leak never darken

struct StripLookNoDarkeningRegressionTests {

    /// Turning bloom and/or light leak on over the same strip (same date,
    /// so the same grain) may only brighten pixels. 1/255 allows for 8-bit
    /// rounding.
    @Test("Bloom and light leak never darken a full strip",
          arguments: StripCustomization.FilmStock.allCases.filter { $0 != .none })
    func bloomAndLeakNeverDarkenAStrip(stock: StripCustomization.FilmStock) throws {
        let scene = try #require(Fixture.scene)
        let photo = Fixture.tagged(scene, .right)
        for blackAndWhite in [false, true] {
            let base = Fixture.customization(
                stock, blackAndWhite: blackAndWhite, effects: .init(halation: true, bloom: false, lightLeak: false)
            )
            let off = try #require(RegressionPixels(Fixture.strip(photo, customization: base)))
            for (bloom, leak) in [(true, false), (false, true), (true, true)] {
                var on = base
                on.effects.bloom = bloom
                on.effects.lightLeak = leak
                let lit = try #require(RegressionPixels(Fixture.strip(photo, customization: on)))
                let darkening = try #require(lit.maxDarkening(comparedTo: off))
                #expect(darkening <= 1, "\(Fixture.describe(on)): darkened a pixel by \(darkening)/255")
                #expect(lit != off, "\(Fixture.describe(on)): effect changed nothing")
            }
        }
    }
}
