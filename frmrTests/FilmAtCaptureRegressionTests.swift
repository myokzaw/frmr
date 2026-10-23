import Foundation
import ImageIO
import Testing
import UIKit
@testable import frmr

// QA-owned v4 Part 2 regressions (frmr-v4-spec.md §F11–F15, §Definition of
// done (Part 2)):
//  - As shot strips with mixed per-photo stocks keep orientation and
//    determinism; an As shot frame equals an override of its own stock
//  - per-photo stock survives entry → StripItem → StripViewModel → strip
//  - the booth paper texture is deterministic across re-renders
//  - renderFullLook (review, thumbnails, Download) keeps a tagged photo's
//    orientation, size and seed determinism, and Download saves the
//    developed photo, upright, never the JPEG preview
//
// Orientation oracle as in StripLookRegressionTests: UIKit's own upright
// copy of a tagged photo.

// MARK: - Helpers

/// RGBA8 sRGB pixels of a CGImage, top row first.
private struct P2Pixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ cgImage: CGImage?) {
        guard let cgImage else { return nil }
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

    init?(_ image: UIImage) { self.init(image.cgImage) }

    func mean(in rect: CGRect) -> (r: Double, g: Double, b: Double) {
        let x0 = max(Int(rect.minX), 0), x1 = min(Int(rect.maxX), width)
        let y0 = max(Int(rect.minY), 0), y1 = min(Int(rect.maxY), height)
        var sum = (r: 0.0, g: 0.0, b: 0.0)
        for y in y0..<y1 {
            for x in x0..<x1 {
                let o = (y * width + x) * 4
                sum = (sum.r + Double(bytes[o]), sum.g + Double(bytes[o + 1]), sum.b + Double(bytes[o + 2]))
            }
        }
        let n = Double(max((x1 - x0) * (y1 - y0), 1))
        return (sum.r / n, sum.g / n, sum.b / n)
    }

    /// Largest per-channel difference inside `rect` (whole image when nil).
    func maxDifference(to other: P2Pixels, in rect: CGRect? = nil) -> Int? {
        guard width == other.width, height == other.height else { return nil }
        let r = rect ?? CGRect(x: 0, y: 0, width: width, height: height)
        var worst = 0
        for y in max(Int(r.minY), 0)..<min(Int(r.maxY), height) {
            for x in max(Int(r.minX), 0)..<min(Int(r.maxX), width) {
                let o = (y * width + x) * 4
                for c in 0..<3 { worst = max(worst, abs(Int(bytes[o + c]) - Int(other.bytes[o + c]))) }
            }
        }
        return worst
    }

    func meanDifference(to other: P2Pixels) -> Double? {
        guard width == other.width, height == other.height else { return nil }
        var total = 0
        for index in bytes.indices where index % 4 != 3 {
            total += abs(Int(bytes[index]) - Int(other.bytes[index]))
        }
        return Double(total) / Double(width * height * 3)
    }
}

private enum P2Fixture {
    typealias Stock = StripCustomization.FilmStock

    static let date = Date(timeIntervalSince1970: 1_790_000_000)
    static let colourStocks: [Stock] = [.daylight200, .portrait400, .cine500T, .slide100]
    static let mixedFilmStocks: [Stock] = [.daylight200, .cine500T, .slide100, .mono3200]
    static let allOn = StripCustomization.FilmEffects(halation: true, bloom: true, lightLeak: true)

    /// Sensor pixels, 128×64: red left half, blue right half. Tagged
    /// `.right` red is the top of the photo; `.left` it is the bottom.
    static func sensor(width: Int = 128, height: Int = 64) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let w = CGFloat(width), h = CGFloat(height)
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
            UIColor.blue.setFill()
            context.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        }.cgImage
    }

    static func tagged(_ cgImage: CGImage, _ orientation: UIImage.Orientation) -> UIImage {
        UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    static func uprightCopy(of image: UIImage) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
        guard let cgImage = drawn.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    static func uprightPixels(_ image: UIImage) -> P2Pixels? {
        uprightCopy(of: image).flatMap { P2Pixels($0) }
    }

    static func strip(
        _ photos: [UIImage], stocks: [Stock], customization: StripCustomization, stripIndex: Int = 0
    ) -> UIImage {
        let cells = zip(photos, stocks).enumerated().map { index, pair in
            StripGenerator.Cell(image: pair.0, caption: "frame \(index)", filmStock: pair.1)
        }
        return StripGenerator.render(strip: cells, customization: customization, date: date, stripIndex: stripIndex)
    }

    static func asShot(blackAndWhite: Bool = false, effects: StripCustomization.FilmEffects = allOn) -> StripCustomization {
        var customization = StripCustomization()
        customization.filmStock = nil
        customization.blackAndWhite = blackAndWhite
        customization.effects = effects
        return customization
    }

    /// Frame `index`'s photo rect in strip pixels.
    static func frameRect(_ index: Int) -> CGRect {
        let rect = StripGenerator.Layout().photoRect(at: index)
        let s = Constants.Strip.renderScale
        return CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s)
    }

    /// Red edge on the expected side of an upright image: colour compares
    /// red against blue, monochrome compares brightness.
    static func redEdgeIsOnTop(_ pixels: P2Pixels, monochrome: Bool, inside rect: CGRect? = nil) -> Bool {
        let r = rect ?? CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        // Stay off the corners and the frame edge (rounded corners, leak)
        let inset = r.insetBy(dx: r.width * 0.2, dy: r.height * 0.05)
        let band = inset.height / 4
        let top = pixels.mean(in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: band))
        let bottom = pixels.mean(in: CGRect(x: inset.minX, y: inset.maxY - band, width: inset.width, height: band))
        if monochrome {
            let lum = { (p: (r: Double, g: Double, b: Double)) in 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }
            return lum(top) > lum(bottom) + 4
        }
        return top.r - top.b > 40 && bottom.b - bottom.r > 40
    }
}

// MARK: - As shot strips (F11/F12)

struct AsShotStripRegressionTests {

    @Test("As shot strip of mixed stocks matches the upright strip", arguments: [false, true])
    func asShotMixedStocksKeepOrientation(blackAndWhite: Bool) throws {
        let sensor = try #require(P2Fixture.sensor())
        let tagged = P2Fixture.tagged(sensor, .right)
        let upright = try #require(P2Fixture.uprightCopy(of: tagged))
        let stocks = P2Fixture.mixedFilmStocks
        let customization = P2Fixture.asShot(blackAndWhite: blackAndWhite)

        let a = try #require(P2Pixels(P2Fixture.strip(Array(repeating: tagged, count: 4), stocks: stocks, customization: customization)))
        let b = try #require(P2Pixels(P2Fixture.strip(Array(repeating: upright, count: 4), stocks: stocks, customization: customization)))
        let difference = try #require(a.maxDifference(to: b))
        #expect(difference <= 2, "As shot B&W:\(blackAndWhite): tagged strip differs from upright by \(difference)/255")

        for (index, stock) in stocks.enumerated() {
            let mono = blackAndWhite || stock.isMonochrome
            #expect(P2Fixture.redEdgeIsOnTop(a, monochrome: mono, inside: P2Fixture.frameRect(index)),
                    "frame \(index) (\(stock.label)) B&W:\(blackAndWhite): red edge not on top")
        }
    }

    @Test func asShotStripWithAnOffFrameStaysUpright() throws {
        let sensor = try #require(P2Fixture.sensor())
        let tagged = P2Fixture.tagged(sensor, .left)
        let upright = try #require(P2Fixture.uprightCopy(of: tagged))
        let stocks: [StripCustomization.FilmStock] = [.none, .portrait400, .mono400, .daylight200]
        let customization = P2Fixture.asShot()

        let a = try #require(P2Pixels(P2Fixture.strip(Array(repeating: tagged, count: 4), stocks: stocks, customization: customization)))
        let b = try #require(P2Pixels(P2Fixture.strip(Array(repeating: upright, count: 4), stocks: stocks, customization: customization)))
        // The Off frame takes UIKit's rotate-and-scale draw, which shifts
        // edges by about a pixel (StripLookRegressionTests); compare means
        let mean = try #require(a.meanDifference(to: b))
        #expect(mean < 1.0, "mean difference \(mean)/255")
        for index in 1..<4 {
            let difference = try #require(a.maxDifference(to: b, in: P2Fixture.frameRect(index)))
            #expect(difference <= 2, "frame \(index) (\(stocks[index].label)) differs by \(difference)/255")
        }
        // .left: red edge at the bottom, so blue is on top
        for (index, stock) in stocks.enumerated() {
            let rect = P2Fixture.frameRect(index)
            let inset = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.05)
            let band = inset.height / 4
            let top = a.mean(in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: band))
            let bottom = a.mean(in: CGRect(x: inset.minX, y: inset.maxY - band, width: inset.width, height: band))
            if stock.isMonochrome {
                #expect(0.2126 * bottom.r + 0.7152 * bottom.g > 0.2126 * top.r + 0.7152 * top.g + 4, "frame \(index)")
            } else {
                #expect(bottom.r - bottom.b > 40 && top.b - top.r > 40, "frame \(index) (\(stock.label)): .left not upright")
            }
        }
    }

    @Test("As shot strip re-renders byte-identically", arguments: [0, 1])
    func asShotStripIsDeterministic(stripIndex: Int) throws {
        let sensor = try #require(P2Fixture.sensor())
        let photos = Array(repeating: P2Fixture.tagged(sensor, .right), count: 4)
        for background in StripCustomization.StripBackground.allCases {
            var customization = P2Fixture.asShot()
            customization.background = background
            let first = try #require(P2Fixture.strip(photos, stocks: P2Fixture.mixedFilmStocks, customization: customization, stripIndex: stripIndex).pngData())
            let second = try #require(P2Fixture.strip(photos, stocks: P2Fixture.mixedFilmStocks, customization: customization, stripIndex: stripIndex).pngData())
            #expect(first == second, "\(background) strip \(stripIndex) is not byte-identical on re-render")
        }
    }

    /// Seeds stay per global frame index, so an As shot strip whose frames
    /// share one stock is byte-identical to overriding the strip with that
    /// stock (whatever the frames' own stocks said).
    @Test("As shot over one stock matches that override exactly",
          arguments: [StripCustomization.FilmStock.portrait400, .none, .mono3200])
    func asShotOverOneStockMatchesThatOverrideExactly(stock: StripCustomization.FilmStock) throws {
        let sensor = try #require(P2Fixture.sensor())
        let photos = Array(repeating: P2Fixture.tagged(sensor, .right), count: 4)
        let asShot = try #require(P2Fixture.strip(
            photos, stocks: Array(repeating: stock, count: 4), customization: P2Fixture.asShot()
        ).pngData())
        var override = P2Fixture.asShot()
        override.filmStock = stock
        let overridden = try #require(P2Fixture.strip(
            photos, stocks: Array(repeating: .portrait400, count: 4), customization: override
        ).pngData())
        #expect(asShot == overridden, "\(stock.label): As shot differs from the override")
    }

    /// Per-photo stock round-trip, mixed frames: each As shot frame renders
    /// exactly as the same frame under an override of its own stock.
    @Test func asShotFrameEqualsAnOverrideOfItsOwnStock() throws {
        let sensor = try #require(P2Fixture.sensor())
        let photos = Array(repeating: P2Fixture.tagged(sensor, .right), count: 4)
        let stocks = P2Fixture.mixedFilmStocks
        let asShot = try #require(P2Pixels(P2Fixture.strip(photos, stocks: stocks, customization: P2Fixture.asShot())))
        for (index, stock) in stocks.enumerated() {
            var override = P2Fixture.asShot()
            override.filmStock = stock
            // Frame stocks deliberately different: the override must win
            let others = Array(repeating: StripCustomization.FilmStock.portrait400, count: 4)
            let overridden = try #require(P2Pixels(P2Fixture.strip(photos, stocks: others, customization: override)))
            let difference = try #require(asShot.maxDifference(to: overridden, in: P2Fixture.frameRect(index)))
            #expect(difference == 0, "frame \(index): As shot \(stock.label) differs from override \(stock.label) by \(difference)")
        }
    }

    /// An override ignores every frame's own stock (Off included).
    @Test("An override ignores every frame stock",
          arguments: [StripCustomization.FilmStock.cine500T, .none, .mono400])
    func overrideIgnoresEveryFrameStock(override stock: StripCustomization.FilmStock) throws {
        let sensor = try #require(P2Fixture.sensor())
        let photos = Array(repeating: P2Fixture.tagged(sensor, .right), count: 4)
        var customization = P2Fixture.asShot()
        customization.filmStock = stock
        let mixed = try #require(P2Fixture.strip(photos, stocks: P2Fixture.mixedFilmStocks, customization: customization).pngData())
        let plain = try #require(P2Fixture.strip(photos, stocks: Array(repeating: .none, count: 4), customization: customization).pngData())
        #expect(mixed == plain, "\(stock.label) override")
    }

    @Test func secondStripDoesNotRepeatTheFirstStripsFrames() throws {
        let sensor = try #require(P2Fixture.sensor())
        let photos = Array(repeating: P2Fixture.tagged(sensor, .right), count: 4)
        let customization = P2Fixture.asShot()
        let first = try #require(P2Pixels(P2Fixture.strip(photos, stocks: P2Fixture.mixedFilmStocks, customization: customization, stripIndex: 0)))
        let second = try #require(P2Pixels(P2Fixture.strip(photos, stocks: P2Fixture.mixedFilmStocks, customization: customization, stripIndex: 1)))
        let difference = try #require(first.maxDifference(to: second, in: P2Fixture.frameRect(0)))
        #expect(difference > 0, "strip 1 frame 0 repeats strip 0 frame 0's grain and leak")
    }
}

// MARK: - Per-photo stock through the app's own plumbing (F11)

@MainActor
struct PerPhotoStockRoundTripRegressionTests {

    @Test func todaysEntriesCarryTheirStockIntoStripItems() {
        let stocks = P2Fixture.mixedFilmStocks
        let entries = stocks.enumerated().map { index, stock in
            DiaryEntry(createdAt: Date.now.addingTimeInterval(Double(index - 10)), photoPath: "missing-\(index).jpg",
                       prompt: "p", response: "r\(index)", filmStock: stock)
        }
        let items = LibraryViewModel.todaysItems(from: entries.reversed())
        #expect(items.map(\.filmStock) == stocks, "oldest-first order with each entry's own stock")
    }

    /// StripViewModel builds its cells from items, so an As shot render
    /// through the view model equals StripGenerator with those stocks.
    @Test func stripViewModelRendersEachItemOnItsOwnStock() async throws {
        let sensor = try #require(P2Fixture.sensor())
        let photo = P2Fixture.tagged(sensor, .right)
        let stocks = P2Fixture.mixedFilmStocks
        let items = stocks.enumerated().map { index, stock in
            StripItem(image: photo, caption: "frame \(index)", entryID: nil, filmStock: stock)
        }
        let viewModel = StripViewModel(items: items, isPhotobooth: true, date: P2Fixture.date)
        // Independent of whatever the simulator's Settings hold
        viewModel.customization = P2Fixture.asShot()
        await viewModel.renderStrips()

        let rendered = try #require(viewModel.stripImages.first)
        let expected = P2Fixture.strip(Array(repeating: photo, count: 4), stocks: stocks, customization: P2Fixture.asShot())
        #expect(rendered.pngData() == expected.pngData())
    }
}

// MARK: - Booth paper (F15)

struct BoothPaperRegressionTests {

    @Test func paperTextureIsDeterministicPerDateAndStrip() throws {
        let size = CGSize(width: 40, height: 60)
        func bytes(_ background: StripCustomization.StripBackground, _ date: Date, _ strip: Int) throws -> [UInt8] {
            let image = try #require(StripGenerator.paperTexture(for: background, size: size, date: date, stripIndex: strip))
            return try #require(P2Pixels(image)).bytes
        }
        for background in StripCustomization.StripBackground.allCases {
            #expect(try bytes(background, P2Fixture.date, 0) == bytes(background, P2Fixture.date, 0))
            #expect(try bytes(background, P2Fixture.date, 0) != bytes(background, P2Fixture.date, 1), "\(background): strip index ignored")
            #expect(try bytes(background, P2Fixture.date, 0) != bytes(background, P2Fixture.date.addingTimeInterval(1), 0),
                    "\(background): another date gives another sheet of paper")

            // There is a texture, and it is faint
            let texture = try #require(StripGenerator.paperTexture(for: background, size: size, date: P2Fixture.date, stripIndex: 0))
            let variance = try #require(PixelBuffer(texture)).luminanceVariance
            #expect(variance > 0, "\(background): no texture")
            #expect(variance < 16, "\(background): texture is not faint, variance \(variance)")
        }
    }

    @Test("Empty booth strip re-renders identically on real paper",
          arguments: StripCustomization.StripBackground.allCases)
    func emptyStripPaperIsDeterministicAndNotPure(background: StripCustomization.StripBackground) throws {
        var customization = StripCustomization()
        customization.background = background
        let cells = Array(repeating: StripGenerator.Cell.empty, count: Constants.entriesPerStrip)
        let first = StripGenerator.render(strip: cells, customization: customization, date: P2Fixture.date)
        let second = StripGenerator.render(strip: cells, customization: customization, date: P2Fixture.date)
        #expect(first.pngData() == second.pngData())

        // The border, outside every frame: paper tone, never pure white/black
        let pixels = try #require(P2Pixels(first))
        let border = Int(Constants.Strip.border * Constants.Strip.renderScale)
        let paper = pixels.mean(in: CGRect(x: 0, y: border * 2, width: max(border - 1, 1), height: 40))
        let channels = [paper.r, paper.g, paper.b]
        #expect(channels.allSatisfy { $0 > 3 && $0 < 252 }, "\(background) paper is pure: \(channels)")
    }
}

// MARK: - Full-frame look (F10/F11/F13)

struct FullLookRegressionTests {

    @Test("renderFullLook keeps orientation tag, size and upright content",
          arguments: StripCustomization.FilmStock.allCases.filter { $0 != .none })
    func fullLookKeepsOrientation(stock: StripCustomization.FilmStock) throws {
        let sensor = try #require(P2Fixture.sensor())
        let orientations: [UIImage.Orientation] = [
            .up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored,
        ]
        for orientation in orientations {
            let tagged = P2Fixture.tagged(sensor, orientation)
            let output = try ImageProcessor.renderFullLook(of: tagged, stock: stock, seed: 7)
            #expect(output.imageOrientation == orientation, "\(stock.label) \(orientation.rawValue): tag lost")
            #expect(output.cgImage?.width == sensor.width && output.cgImage?.height == sensor.height,
                    "\(stock.label) \(orientation.rawValue): full-resolution size changed")
            #expect(output.size == tagged.size, "\(stock.label) \(orientation.rawValue): point size changed")

            // Content: the look of the tagged photo, resolved by UIKit, must
            // have the same layout as UIKit's upright copy of the original
            let shown = try #require(P2Fixture.uprightPixels(output))
            let original = try #require(P2Fixture.uprightPixels(tagged))
            // 2×2 quadrants: wherever the original is clearly red or blue,
            // the rendered look must lean the same way (colour stocks)
            if !stock.isMonochrome {
                for qy in 0..<2 {
                    for qx in 0..<2 {
                        let quadrant = CGRect(
                            x: shown.width * qx / 2, y: shown.height * qy / 2,
                            width: shown.width / 2, height: shown.height / 2
                        ).insetBy(dx: 4, dy: 4)
                        let a = shown.mean(in: quadrant), b = original.mean(in: quadrant)
                        guard abs(b.r - b.b) > 100 else { continue }
                        #expect((a.r - a.b > 0) == (b.r - b.b > 0),
                                "\(stock.label) \(orientation.rawValue): quadrant \(qx),\(qy) red/blue flipped")
                    }
                }
            }
            if orientation == .right || orientation == .left {
                let pixels = shown
                let redOnTop = orientation == .right
                let half = pixels.height / 2
                let top = pixels.mean(in: CGRect(x: 0, y: 0, width: pixels.width, height: half / 2))
                let bottom = pixels.mean(in: CGRect(x: 0, y: pixels.height - half / 2, width: pixels.width, height: half / 2))
                let (red, blue) = redOnTop ? (top, bottom) : (bottom, top)
                if stock.isMonochrome {
                    #expect(0.2126 * red.r + 0.7152 * red.g > 0.2126 * blue.r + 0.7152 * blue.g + 4,
                            "\(stock.label) \(orientation.rawValue)")
                } else {
                    #expect(red.r - red.b > 40 && blue.b - blue.r > 40, "\(stock.label) \(orientation.rawValue)")
                }
            }
        }
    }

    /// Same seed, same bytes; another seed, another grain. Default strengths
    /// and a boosted set (every effect on, vignette included) per stock.
    @Test("renderFullLook is seed-deterministic", arguments: StripCustomization.FilmStock.allCases.filter { $0 != .none }, [false, true])
    func fullLookIsSeedDeterministic(stock: StripCustomization.FilmStock, boosted: Bool) throws {
        let sensor = try #require(P2Fixture.sensor())
        let tagged = P2Fixture.tagged(sensor, .right)
        var look = FilmLook.stockDefaults(for: stock)
        if boosted {
            look.strengths = .init(halation: 0.8, haze: 0.6, lightLeak: 0.7, grain: 1.2, vignette: 0.5)
        }
        let a = try ImageProcessor.renderFullLook(of: tagged, look: look, seed: 42)
        let b = try ImageProcessor.renderFullLook(of: tagged, look: look, seed: 42)
        let other = try ImageProcessor.renderFullLook(of: tagged, look: look, seed: 43)
        #expect(P2Pixels(a) == P2Pixels(b), "\(stock.label) boosted:\(boosted): same seed differs")
        #expect(P2Pixels(a) != P2Pixels(other), "\(stock.label) boosted:\(boosted): seed ignored")
    }

    @Test func displaySizedFullLookKeepsOrientation() throws {
        let sensor = try #require(P2Fixture.sensor(width: 256, height: 128))
        for (orientation, redOnTop) in [(UIImage.Orientation.right, true), (.left, false)] {
            let tagged = P2Fixture.tagged(sensor, orientation)
            let output = try ImageProcessor.renderFullLook(
                of: tagged, stock: .daylight200, seed: 3, coveringPixelSize: CGSize(width: 32, height: 64)
            )
            #expect(output.imageOrientation == orientation)
            #expect(output.size.width >= 32 && output.size.height >= 64 && output.size.width < 128,
                    "display render should shrink to cover 32×64, got \(output.size)")
            let pixels = try #require(P2Fixture.uprightPixels(output))
            let upright = redOnTop
            let top = pixels.mean(in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height / 4))
            let bottom = pixels.mean(in: CGRect(x: 0, y: pixels.height * 3 / 4, width: pixels.width, height: pixels.height / 4))
            let (red, blue) = upright ? (top, bottom) : (bottom, top)
            #expect(red.r - red.b > 40 && blue.b - blue.r > 40, "\(orientation.rawValue) display render not upright")
        }
    }

    @Test func heicKeepsTheOrientationTag() throws {
        let sensor = try #require(P2Fixture.sensor())
        for orientation in [UIImage.Orientation.right, .left, .up] {
            let look = try ImageProcessor.renderFullLook(of: P2Fixture.tagged(sensor, orientation), stock: .slide100, seed: 1)
            let data = try ImageProcessor.heicData(from: look)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.heic", "\(orientation.rawValue): not HEIC")
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            let tag = properties[kCGImagePropertyOrientation] as? UInt32
            #expect(tag == ImageProcessor.cgOrientation(from: orientation).rawValue, "\(orientation.rawValue): HEIC tag")
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == sensor.width && decoded.height == sensor.height, "HEIC stores sensor pixels")
        }
    }
}

// MARK: - Download saves the developed photo, upright (F13)

@MainActor
struct DownloadRegressionTests {

    private final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [Data] = []
        func append(_ data: Data) { lock.withLock { items.append(data) } }
        var all: [Data] { lock.withLock { items } }
    }

    @Test func downloadWaitsForTheRAWAndSavesItUpright() async throws {
        let preview = try #require(P2Fixture.sensor())
        // The "developed RAW": same layout, but green instead of red, so the
        // saved file shows which one was used
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let developedCG = try #require(UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 64, y: 0, width: 64, height: 64))
        }.cgImage)
        let developed = P2Fixture.tagged(developedCG, .right)
        let development = Task<UIImage, Never> {
            try? await Task.sleep(for: .milliseconds(300))
            return developed
        }
        let saved = Saved()
        let review = PhotoEditViewModel(
            preview: P2Fixture.tagged(preview, .right), stock: .portrait400, captureDate: P2Fixture.date,
            development: development, savePhotoData: { saved.append($0) }
        )

        await review.download()

        #expect(saved.all.count == 1)
        #expect(review.didSaveDownload)
        let data = try #require(saved.all.first)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let tag = try #require(properties[kCGImagePropertyOrientation] as? UInt32)
        let cgTag = try #require(CGImagePropertyOrientation(rawValue: tag))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let shown = UIImage(cgImage: decoded, scale: 1, orientation: ImageProcessor.uiOrientation(from: cgTag))
        let pixels = try #require(P2Fixture.uprightPixels(shown))
        #expect(pixels.width == 64 && pixels.height == 128, "full resolution, upright 64×128")
        let top = pixels.mean(in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height / 4))
        let bottom = pixels.mean(in: CGRect(x: 0, y: pixels.height * 3 / 4, width: pixels.width, height: pixels.height / 4))
        #expect(top.g > top.r + 40, "saved photo must be the developed RAW (green), on top: \(top)")
        #expect(bottom.b > bottom.g + 40, "blue half must be at the bottom: \(bottom)")
    }
}
