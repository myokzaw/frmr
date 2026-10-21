import AVFoundation
import CoreImage
import Metal
import ImageIO
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// In-memory SwiftData store: proves the schema and save/fetch/delete paths
// work without touching the app's real store
struct PersistenceTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test func diaryEntryRoundTrips() throws {
        let context = try makeContext()
        let entry = DiaryEntry(
            photoPath: "Photos/test.jpg",
            prompt: "What made you take this picture?",
            response: "The light."
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiaryEntry>())

        #expect(fetched.count == 1)
        #expect(fetched[0].id == entry.id)
        #expect(fetched[0].photoPath == "Photos/test.jpg")
        #expect(fetched[0].prompt == "What made you take this picture?")
        #expect(fetched[0].response == "The light.")
    }

    @Test func dailyStripRoundTripsOrderedEntryIDs() throws {
        let context = try makeContext()
        let ids = [UUID(), UUID(), UUID(), UUID()]
        context.insert(DailyStrip(entryIDs: ids, isPhotobooth: false))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyStrip>())

        #expect(fetched.count == 1)
        #expect(fetched[0].entryIDs == ids)
        #expect(fetched[0].isPhotobooth == false)
        #expect(fetched[0].imageRelativePath == "Strips/\(fetched[0].id.uuidString).png")
    }

    @Test func deleteAllClearsBothModels() throws {
        // The path Settings' "Clear diary" relies on
        let context = try makeContext()
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R"))
        context.insert(DailyStrip(entryIDs: [], isPhotobooth: true))
        try context.save()

        try context.delete(model: DiaryEntry.self)
        try context.delete(model: DailyStrip.self)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).isEmpty)
    }

    @Test func entriesSortNewestFirstLikeTheLibraryQuery() throws {
        let context = try makeContext()
        let older = DiaryEntry(createdAt: .now.addingTimeInterval(-3600), photoPath: "Photos/old.jpg", prompt: "P", response: "old")
        let newer = DiaryEntry(createdAt: .now, photoPath: "Photos/new.jpg", prompt: "P", response: "new")
        context.insert(older)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.response) == ["new", "old"])
    }
}

struct StripGeneratorTests {

    private func makeCells(_ count: Int) -> [StripGenerator.Cell] {
        (0..<count).map { StripGenerator.Cell(image: nil, caption: "caption \($0)") }
    }

    @Test func fourEntriesMakeOneFullStrip() {
        let strips = StripGenerator.chunked(makeCells(4), paddingWith: .empty)

        #expect(strips.count == 1)
        #expect(strips[0].count == Constants.entriesPerStrip)
        #expect(strips[0].allSatisfy { !$0.caption.isEmpty })
    }

    @Test func fiveEntriesMakeTwoStripsSecondPaddedWithThreeEmptyCells() {
        let strips = StripGenerator.chunked(makeCells(5), paddingWith: .empty)

        #expect(strips.count == 2)
        #expect(strips[1].count == Constants.entriesPerStrip)
        #expect(strips[1][0].caption == "caption 4")

        let emptyCells = strips[1].filter { $0.caption.isEmpty && $0.image == nil }
        #expect(emptyCells.count == 3)
    }

    @Test func zeroEntriesMakeNoStrips() {
        let strips = StripGenerator.chunked(makeCells(0), paddingWith: .empty)

        #expect(strips.isEmpty)
    }

    @Test func renderedStripHasSpecWidth() {
        let image = StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: .now
        )

        #expect(image.size.width == Constants.Strip.width)
        #expect(image.size.height > 0)
        #expect(image.scale == Constants.Strip.renderScale)
    }

    // MARK: v4 F8 / F15 — plain booth strip

    private enum PlainGeometry {
        static let layout = StripGenerator.Layout()
        static let scale = Constants.Strip.renderScale

        /// Photo slots in pixels, grown by a pixel for edge antialiasing.
        static var photoRects: [CGRect] {
            (0..<Constants.entriesPerStrip).map { index in
                let rect = layout.photoRect(at: index)
                return CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
                    .insetBy(dx: -1, dy: -1)
            }
        }

        /// The bottom date stamp's full-width band, in pixels.
        static var dateBand: Range<Int> {
            let date = layout.dateRect
            return Int(floor(date.minY * scale)) - 1 ..< Int(ceil(date.maxY * scale)) + 1
        }
    }

    // Empty captions, so the caption bands must be plain paper too: that is
    // where v2's frame numbers were printed. The paper carries a faint
    // texture (v4 F15), so "plain" means within its amplitude of the tone.
    @Test(arguments: [StripCustomization.StripBackground.white, .black])
    func plainStripHasNoMarksOutsidePhotosAndText(background: StripCustomization.StripBackground) throws {
        var customization = StripCustomization()
        customization.background = background
        let strip = StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: customization,
            date: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let buffer = try #require(PixelBuffer(strip))
        let paper = background.paperRGB
        let tolerance = Constants.Strip.paperTextureAmplitude * 255 + 1.5

        let excluded = PlainGeometry.photoRects
        let dateBand = PlainGeometry.dateBand
        var marks = 0
        for y in 0..<buffer.height where !dateBand.contains(y) {
            for x in 0..<buffer.width {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                guard !excluded.contains(where: { $0.contains(point) }) else { continue }
                let pixel = buffer.rgb(x: x, y: y)
                if abs(pixel.r - paper.r * 255) > tolerance || abs(pixel.g - paper.g * 255) > tolerance
                    || abs(pixel.b - paper.b * 255) > tolerance {
                    marks += 1
                }
            }
        }
        #expect(marks == 0, "\(marks) pixels differ from the paper outside photos and text")
    }

    @Test func theDateStampIsStillPrinted() throws {
        let buffer = try #require(PixelBuffer(StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: Date(timeIntervalSince1970: 1_790_000_000)
        )))
        let inked = PlainGeometry.dateBand.contains { y in
            (0..<buffer.width).contains { x in buffer.rgb(x: x, y: y).r < 128 }
        }
        #expect(inked, "no date stamp in the bottom band")
    }
}

// MARK: - v4 F15: booth strip

struct BoothStripTests {

    private let layout = StripGenerator.Layout()
    private typealias S = Constants.Strip

    @Test func framesArePortraitFourByFive() {
        for index in 0..<Constants.entriesPerStrip {
            let frame = layout.photoRect(at: index)
            #expect(abs(frame.width / frame.height - 4.0 / 5.0) < 1e-9)
        }
        #expect(S.cellAspectRatio == 0.8)
    }

    @Test func borderAndGapsMatchTheirConstants() {
        let first = layout.photoRect(at: 0)
        #expect(first.minX == S.border && first.minY == S.border)
        #expect(S.width - first.maxX == S.border, "the border is even left and right")
        for index in 0..<Constants.entriesPerStrip {
            let caption = layout.captionRect(at: index)
            #expect(caption.minY - layout.photoRect(at: index).maxY == S.captionSpacing, "caption sits under its frame")
            if index + 1 < Constants.entriesPerStrip {
                #expect(abs(layout.photoRect(at: index + 1).minY - caption.maxY - S.frameGap) < 1e-9)
            }
        }
        let lastCaption = layout.captionRect(at: Constants.entriesPerStrip - 1)
        #expect(abs(layout.dateRect.minY - lastCaption.maxY - S.frameGap) < 1e-9)
        #expect(abs(layout.totalSize.height - layout.dateRect.maxY - S.border) < 1e-9)
        #expect(S.border <= 8 && S.frameGap <= 6, "a booth strip's border and gaps are thin")
    }

    @Test func paperIsNeitherPureWhiteNorPureBlack() throws {
        for background in StripCustomization.StripBackground.allCases {
            var customization = StripCustomization()
            customization.background = background
            let buffer = try #require(PixelBuffer(StripGenerator.render(
                strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
                customization: customization, date: Date(timeIntervalSince1970: 1_790_000_000)
            )))
            let corner = buffer.rgb(x: 2, y: 2)
            if background == .white {
                #expect(corner.r < 252 && corner.b < 240 && corner.r > 225, "warm off-white, got \(corner)")
                #expect(corner.r > corner.b, "the white paper is warm")
            } else {
                #expect(corner.r > 10 && corner.r < 40, "near-black, got \(corner)")
            }
        }
    }

    @Test func paperTextureIsDeterministicPerDateAndFaint() throws {
        let size = CGSize(width: 40, height: 40)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let first = try #require(StripGenerator.paperTexture(for: .white, size: size, date: date, stripIndex: 0))
        let again = try #require(StripGenerator.paperTexture(for: .white, size: size, date: date, stripIndex: 0))
        let other = try #require(StripGenerator.paperTexture(for: .white, size: size, date: date.addingTimeInterval(1), stripIndex: 0))
        let a = try #require(PixelBuffer(UIImage(cgImage: first)))
        let b = try #require(PixelBuffer(UIImage(cgImage: again)))
        let c = try #require(PixelBuffer(UIImage(cgImage: other)))
        #expect(a == b)
        #expect(a != c, "another date gives another sheet of paper")
        #expect(a.luminanceVariance > 0, "there is a texture")
        #expect(a.luminanceVariance < 16, "and it is faint")

        let strip = { StripGenerator.render(strip: [.empty], customization: StripCustomization(), date: date).pngData() }
        #expect(strip() == strip())
    }
}

// MARK: - v4 F8: background migration

struct StripBackgroundMigrationTests {

    private typealias Background = StripCustomization.StripBackground

    @Test func storedCreamAndUnknownValuesReadAsWhite() {
        #expect(Background(settingsName: "cream") == .white)
        #expect(Background(settingsName: "teal") == .white)
        #expect(Background(settingsName: nil) == .white)
        #expect(Background(settingsName: "white") == .white)
        #expect(Background(settingsName: "black") == .black)
    }

    @Test func pickersOfferWhiteThenBlackAndTheyRoundTrip() {
        #expect(Background.allCases == [.white, .black])
        for background in Background.allCases {
            #expect(Background(settingsName: background.settingsName) == background)
        }
        #expect(StripCustomization().background == .white)
    }

    @Test func textContrastsWithEachBackground() {
        #expect(Background.white.contrastingTextColor == .appBlack)
        #expect(Background.black.contrastingTextColor == .appCream)
    }

    @Test func storedCreamIsRewrittenToWhiteAtLaunch() throws {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("cream", forKey: Constants.DefaultsKeys.stripBackground)

        #expect(StripViewModel.loadDefaults(from: defaults).background == .white)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripBackground) == "white")

        defaults.set("black", forKey: Constants.DefaultsKeys.stripBackground)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripBackground) == "black")
    }
}

// MARK: - v2 helpers

// Minimal RGBA pixel reader so the rendering tests can assert on real output
// rather than on the code that produced it.
private struct PixelBuffer: Equatable {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = raw
    }

    func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]))
    }

    /// Variance of per-pixel luminance — how much grain is present.
    var luminanceVariance: Double {
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                values.append(0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    var channelMeans: (r: Double, g: Double, b: Double) {
        var totals = (r: 0.0, g: 0.0, b: 0.0)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                totals.r += pixel.r
                totals.g += pixel.g
                totals.b += pixel.b
            }
        }
        let count = Double(width * height)
        return (totals.r / count, totals.g / count, totals.b / count)
    }
}

private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - v2 F4 / F5: grain and film stocks

struct ImageProcessorTests {

    private func variance(of stock: StripCustomization.FilmStock, on color: UIColor) throws -> Double {
        var customization = StripCustomization()
        customization.filmStock = stock
        let output = ImageProcessor.applyStripLook(to: solidImage(color), customization: customization, outputWidth: 64)
        let buffer = try #require(PixelBuffer(output))
        return buffer.luminanceVariance
    }

    @Test func heavierStockProducesMoreGrainThanFinerStock() throws {
        let fine = try variance(of: .slide100, on: .black)
        let heavy = try variance(of: .mono3200, on: .black)

        #expect(heavy > fine)
    }

    @Test func filmStockNoneLeavesTheImageUntouched() throws {
        var customization = StripCustomization()
        customization.filmStock = StripCustomization.FilmStock.none
        let input = solidImage(UIColor(white: 0.5, alpha: 1))
        let output = ImageProcessor.applyStripLook(to: input, customization: customization, outputWidth: 32)

        #expect(output === input)
    }

    // v4 F3: the colour now comes from the film cube's crossovers, so it
    // shows on a light tone rather than as a flat cast on mid grey.
    // (Replaces v2's warmStocksPushRedAboveBlueAndNeutralStocksDoNot; the
    // model-level twin is FilmModelTests.crossoversGive…)
    @Test func filmCubeRendersDaylightWarmAndCineCoolOnALightTone() throws {
        let light = UIColor(white: 0.8, alpha: 1)
        func means(_ stock: StripCustomization.FilmStock) throws -> (r: Double, g: Double, b: Double) {
            var customization = StripCustomization()
            customization.filmStock = stock
            let output = ImageProcessor.applyStripLook(to: solidImage(light), customization: customization, outputWidth: 64)
            return try #require(PixelBuffer(output)).channelMeans
        }
        let daylight = try means(.daylight200)
        let cine = try means(.cine500T)
        #expect(daylight.r > daylight.b, "Daylight 200 should read warm")
        #expect(cine.b > cine.r, "Cine 500T should read cool")
    }

    @Test func monochromeThroughTheCubeIsNeutral() throws {
        var customization = StripCustomization()
        customization.filmStock = .portrait400
        customization.blackAndWhite = true
        let colourful = solidImage(UIColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        let buffer = try #require(PixelBuffer(
            ImageProcessor.applyStripLook(to: colourful, customization: customization, outputWidth: 64)
        ))
        let means = buffer.channelMeans
        #expect(abs(means.r - means.g) < 2 && abs(means.g - means.b) < 2)
    }

    // A landscape- or diagonally-held capture is recorded as an EXIF tag, so
    // this mapping is what decides whether the developed RAW reads upright.
    // The two enums share case names but not raw values — bridging through
    // rawValue would silently turn .right into .downMirrored.
    @Test func exifOrientationMapsOntoTheMatchingUIImageOrientation() {
        let expected: [(CGImagePropertyOrientation, UIImage.Orientation)] = [
            (.up, .up),
            (.upMirrored, .upMirrored),
            (.down, .down),
            (.downMirrored, .downMirrored),
            (.leftMirrored, .leftMirrored),
            (.right, .right),
            (.rightMirrored, .rightMirrored),
            (.left, .left),
        ]
        for (exif, ui) in expected {
            #expect(ImageProcessor.uiOrientation(from: exif) == ui)
        }
    }

    // The four upright quarter-turns must stay distinct: collapsing any two
    // is what a sign-convention slip looks like, and it would rotate every
    // landscape capture the wrong way rather than failing loudly.
    @Test func theFourQuarterTurnsAreDistinct() {
        let quarterTurns: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let mapped = quarterTurns.map(ImageProcessor.uiOrientation(from:))
        #expect(Set(mapped.map(\.rawValue)).count == quarterTurns.count)
    }

    @Test func cgOrientationRoundTripsEveryCase() {
        let all: [CGImagePropertyOrientation] = [
            .up, .upMirrored, .down, .downMirrored, .leftMirrored, .right, .rightMirrored, .left,
        ]
        for exif in all {
            #expect(ImageProcessor.cgOrientation(from: ImageProcessor.uiOrientation(from: exif)) == exif)
        }
    }

    // Regression (v4 F0): captures are unrotated pixels plus a tag, and the
    // strip look used to drop the tag — a landscape-held photo came back on
    // its side as soon as grain or B&W was on.
    @Test func stripLookKeepsATaggedPhotoUpright() throws {
        // Sensor-space pixels: red on the left, blue on the right. Tagged
        // .right, the left edge reads as the top of the photo.
        let sensorSize = CGSize(width: 64, height: 32)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let sensor = UIGraphicsImageRenderer(size: sensorSize, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        }
        let cgImage = try #require(sensor.cgImage)
        let tagged = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        // Since F1 the result is the slot-sized centre crop of the upright
        // photo: 32×64 upright → a 32×32 square from its middle, red on top.
        let slotWidth: CGFloat = 32
        let slotHeight = (slotWidth / Constants.Strip.cellAspectRatio).rounded()
        for blackAndWhite in [false, true] {
            var customization = StripCustomization()
            customization.filmStock = .daylight200
            customization.blackAndWhite = blackAndWhite
            let output = ImageProcessor.applyStripLook(to: tagged, customization: customization, outputWidth: slotWidth)

            #expect(output.imageOrientation == .up)
            let buffer = try #require(PixelBuffer(output))
            #expect(buffer.width == Int(slotWidth) && buffer.height == Int(slotHeight),
                    "B&W \(blackAndWhite): output must be the slot size")
            if !blackAndWhite {
                // Left and right of the top row agree: a sideways photo would
                // put red on one side and blue on the other instead
                let topLeft = buffer.rgb(x: 4, y: 4)
                let topRight = buffer.rgb(x: Int(slotWidth) - 5, y: 4)
                let bottom = buffer.rgb(x: Int(slotWidth) / 2, y: Int(slotHeight) - 5)
                #expect(topLeft.r > topLeft.b && topRight.r > topRight.b,
                        "top of the upright photo should be the red edge")
                #expect(bottom.b > bottom.r, "bottom of the upright photo should be the blue edge")
            }
        }
    }

    // MARK: v4 F1 — downscale first

    @Test func resizedToSlotFillsAndCentreCropsTheSlot() throws {
        // 400×100 wide source, slot 50 px wide: the fill scale is set by the
        // height, and the crop takes the middle 50 px of the 200 px width
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 100))
        let slot = try #require(ImageProcessor.resizedToSlot(source, outputWidth: 50))
        let expectedHeight = (50 / Constants.Strip.cellAspectRatio).rounded()

        #expect(slot.extent == CGRect(x: 0, y: 0, width: 50, height: expectedHeight))
    }

    @Test func resizedToSlotRejectsAnEmptyOrInfiniteSource() {
        #expect(ImageProcessor.resizedToSlot(CIImage(color: .white), outputWidth: 50) == nil)
        #expect(ImageProcessor.resizedToSlot(CIImage.empty(), outputWidth: 50) == nil)
    }

    @Test func stripLookIsRenderedAtTheSlotSizeNotTheSourceSize() throws {
        var customization = StripCustomization()
        customization.filmStock = .portrait400
        let large = solidImage(UIColor(white: 0.5, alpha: 1), size: CGSize(width: 640, height: 480))
        let output = ImageProcessor.applyStripLook(to: large, customization: customization, outputWidth: 60)
        let buffer = try #require(PixelBuffer(output))

        #expect(buffer.width == 60)
        #expect(buffer.height == Int((60 / Constants.Strip.cellAspectRatio).rounded()))
    }

    @Test func stripLookIsDeterministic() throws {
        var customization = StripCustomization()
        customization.filmStock = .mono3200
        let input = solidImage(UIColor(white: 0.4, alpha: 1), size: CGSize(width: 200, height: 150))
        let first = try #require(PixelBuffer(ImageProcessor.applyStripLook(to: input, customization: customization, outputWidth: 48)))
        let second = try #require(PixelBuffer(ImageProcessor.applyStripLook(to: input, customization: customization, outputWidth: 48)))

        #expect(first == second)
    }

    @Test func liveGrainTileShiftsBetweenFrames() throws {
        // v2 F6: a tile that doesn't move between frames reads as a filter
        let size = CGSize(width: 32, height: 32)
        let first = try #require(ImageProcessor.makeLiveGrainTile(size: size, phase: 0))
        let second = try #require(ImageProcessor.makeLiveGrainTile(size: size, phase: 37))

        let a = try #require(PixelBuffer(UIImage(cgImage: first)))
        let b = try #require(PixelBuffer(UIImage(cgImage: second)))
        let differs = (0..<size.height.intValue).contains { y in
            (0..<size.width.intValue).contains { x in a.rgb(x: x, y: y) != b.rgb(x: x, y: y) }
        }

        #expect(differs)
    }
}

private extension CGFloat {
    var intValue: Int { Int(self) }
}

// MARK: - v4 F1: superseded renders

@MainActor
struct StripViewModelRenderTests {

    @Test func aSupersededRenderLeavesTheNewestInCharge() async {
        let photo = solidImage(UIColor(white: 0.5, alpha: 1), size: CGSize(width: 320, height: 240))
        let items = (0..<Constants.entriesPerStrip).map { _ in StripItem(image: photo, caption: "", entryID: nil) }
        let viewModel = StripViewModel(items: items, isPhotobooth: true)
        viewModel.customization.filmStock = .portrait400

        let first = Task { await viewModel.renderStrips() }
        viewModel.customization.blackAndWhite = true
        await viewModel.renderStrips()
        await first.value

        #expect(!viewModel.isRendering)
        #expect(viewModel.stripImages.count == 1)
    }
}

// MARK: - v2 F5: film stock migration

struct FilmStockMigrationTests {

    private typealias FilmStock = StripCustomization.FilmStock
    private typealias PrintStock = StripCustomization.PrintStock

    @Test func legacyGrainToggleMapsOntoTheClosestStock() {
        #expect(FilmStock.migrating(fromLegacyGrainEnabled: false) == .none)
        // v2 mapped "on" to ISO 400, which v4 maps to Portrait 400
        #expect(FilmStock.migrating(fromLegacyGrainEnabled: true) == .portrait400)
    }

    // v4 F7 (OPEN v4-6): stored v2 raw values
    @Test func storedV2StocksMigrateToTheirV4Equivalents() {
        #expect(FilmStock.migrating(fromStoredValue: "iso100") == .daylight200)
        #expect(FilmStock.migrating(fromStoredValue: "iso400") == .portrait400)
        #expect(FilmStock.migrating(fromStoredValue: "iso3200") == .cine500T)
        #expect(FilmStock.migrating(fromStoredValue: "none") == .none)
    }

    @Test func unknownOrMissingStoredValuesMigrateToOff() {
        #expect(FilmStock.migrating(fromStoredValue: "iso800") == .none)
        #expect(FilmStock.migrating(fromStoredValue: "") == .none)
        #expect(FilmStock.migrating(fromStoredValue: nil) == .none)
    }

    @Test func currentRawValuesRoundTrip() {
        for stock in FilmStock.allCases {
            #expect(FilmStock.migrating(fromStoredValue: stock.rawValue) == stock)
        }
    }

    @Test func decodingAppliesTheSameMigration() throws {
        let decoded = try JSONDecoder().decode([FilmStock].self, from: Data(#"["iso400","cine500T","bogus"]"#.utf8))
        #expect(decoded == [.portrait400, .cine500T, .none])
    }

    @Test func everyStockExceptNoneHasCurvesGrainAndADefaultPrint() {
        for stock in FilmStock.allCases {
            let isOff = stock == .none
            #expect((stock.negative == nil) == isOff, "\(stock.label) curves")
            #expect((stock.grainIntensity > 0) == !isOff, "\(stock.label) grain")
            #expect((stock.defaultPrint == nil) == isOff, "\(stock.label) default print")
            #expect((stock.iso == nil) == isOff, "\(stock.label) ISO")
        }
    }

    @Test func launchSetMatchesTheSpecTable() {
        #expect(FilmStock.allCases.map(\.label) == [
            "Off", "Daylight 200", "Portrait 400", "Cine 500T", "Slide 100", "Mono 400", "Mono 3200",
        ])
        #expect(PrintStock.allCases.map(\.label) == ["Lab print", "Cinema print", "Matte paper", "Projection"])
        #expect(FilmStock.allCases.compactMap(\.iso) == [200, 400, 500, 100, 400, 3200])
        #expect(FilmStock.allCases.filter(\.isMonochrome) == [.mono400, .mono3200])
    }

    @Test func eachStockHasItsSpecDefaultPrint() {
        #expect(FilmStock.daylight200.defaultPrint == .lab)
        #expect(FilmStock.portrait400.defaultPrint == .lab)
        #expect(FilmStock.cine500T.defaultPrint == .cinema)
        #expect(FilmStock.slide100.defaultPrint == .projection)
        #expect(FilmStock.mono400.defaultPrint == .lab)
        #expect(FilmStock.mono3200.defaultPrint == .lab)
    }

    @Test func projectionIsSlideOnlyAndSlideIsProjectionOnly() {
        #expect(FilmStock.slide100.availablePrints == [.projection])
        #expect(FilmStock.none.availablePrints.isEmpty)
        for stock in FilmStock.allCases where stock != .none && stock != .slide100 {
            #expect(stock.availablePrints == [.lab, .cinema, .matte], "\(stock.label)")
        }
    }

    @Test func aNilPrintResolvesToTheStocksDefault() {
        for stock in FilmStock.allCases {
            var customization = StripCustomization()
            customization.filmStock = stock
            customization.printStock = nil
            #expect(customization.resolvedPrint == stock.defaultPrint, "\(stock.label)")
        }
    }

    @Test func aPrintTheStockCannotUseFallsBackToItsDefault() {
        var customization = StripCustomization()
        customization.filmStock = .slide100
        customization.printStock = .matte
        #expect(customization.resolvedPrint == .projection)

        customization.filmStock = .daylight200
        customization.printStock = .projection
        #expect(customization.resolvedPrint == .lab)

        customization.printStock = .matte
        #expect(customization.resolvedPrint == .matte)
    }

    @Test func effectDefaultsArePerSpec() {
        // Halation on for every stock (each at its own strength, Cine 500T
        // strongest); bloom and light leak opt-in
        for stock in FilmStock.allCases {
            let effects = StripCustomization.FilmEffects.defaults(for: stock)
            #expect(effects.halation && !effects.bloom && !effects.lightLeak, "\(stock.label)")
        }
        #expect(StripCustomization().effects == .stockDefaults)
    }

    @Test func monochromeStocksAlwaysRenderInBlackAndWhite() {
        var customization = StripCustomization()
        customization.blackAndWhite = false
        customization.filmStock = .mono400
        #expect(customization.rendersInBlackAndWhite)
        customization.filmStock = .daylight200
        #expect(!customization.rendersInBlackAndWhite)
        customization.blackAndWhite = true
        #expect(customization.rendersInBlackAndWhite)
    }
}

// MARK: - v4 F7: strip defaults persistence

struct StripDefaultsTests {

    private func scratchDefaults() throws -> UserDefaults {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func emptyStoreLoadsTheSpecDefaults() throws {
        let loaded = StripViewModel.loadDefaults(from: try scratchDefaults())
        #expect(loaded == StripCustomization())
        #expect(loaded.effects.halation, "a missing halation key means the stock default, which is on")
    }

    @Test func storedDefaultsRoundTrip() throws {
        let defaults = try scratchDefaults()
        var customization = StripCustomization()
        customization.background = .black
        customization.filmStock = .cine500T
        customization.printStock = .matte
        customization.effects = .init(halation: false, bloom: true, lightLeak: true)
        customization.blackAndWhite = true

        StripViewModel.storeDefaults(customization, in: defaults)
        #expect(StripViewModel.loadDefaults(from: defaults) == customization)

        customization.printStock = nil
        StripViewModel.storeDefaults(customization, in: defaults)
        #expect(StripViewModel.loadDefaults(from: defaults).printStock == nil)
    }

    @Test func v2StockKeyMigratesOnLoadAndInPlace() throws {
        let defaults = try scratchDefaults()
        defaults.set("iso3200", forKey: Constants.DefaultsKeys.stripFilmStock)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == .cine500T)

        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "cine500T")
        // Idempotent
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "cine500T")
    }

    @Test func preV2GrainKeyMigratesInPlace() throws {
        let defaults = try scratchDefaults()
        defaults.set(true, forKey: Constants.DefaultsKeys.stripFilmGrain)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock) == "portrait400")
    }

    @Test func aFreshInstallStoresNothing() throws {
        let defaults = try scratchDefaults()
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.object(forKey: Constants.DefaultsKeys.stripFilmStock) == nil)
    }
}

// MARK: - v4 F7: controls card state

@MainActor
struct StripControlsStateTests {

    private func viewModel(_ stock: StripCustomization.FilmStock) -> StripViewModel {
        let viewModel = StripViewModel(items: [], isPhotobooth: true)
        viewModel.customization = StripCustomization()
        viewModel.customization.filmStock = stock
        return viewModel
    }

    @Test func printPickerIsHiddenForOffAndSlide() {
        #expect(!viewModel(.none).isPrintPickerVisible)
        #expect(!viewModel(.slide100).isPrintPickerVisible)
        #expect(viewModel(.daylight200).isPrintPickerVisible)
        #expect(viewModel(.mono3200).isPrintPickerVisible)
    }

    @Test func effectsAreHiddenOnlyWithTheStockOff() {
        #expect(!viewModel(.none).areEffectsVisible)
        for stock in StripCustomization.FilmStock.allCases where stock != .none {
            #expect(viewModel(stock).areEffectsVisible)
        }
    }

    @Test func selectedPrintIsAlwaysOneOfTheAvailablePrints() {
        let model = viewModel(.cine500T)
        #expect(model.selectedPrint == .cinema)
        model.selectedPrint = .matte
        #expect(model.customization.printStock == .matte)
        #expect(model.availablePrints.contains(model.selectedPrint))
    }

    @Test func blackAndWhiteIsLockedOnForMonochromeStocks() {
        let model = viewModel(.mono400)
        #expect(model.isBlackAndWhiteLocked)
        #expect(model.blackAndWhiteToggle)
        model.blackAndWhiteToggle = false
        #expect(model.blackAndWhiteToggle)

        let colour = viewModel(.portrait400)
        #expect(!colour.isBlackAndWhiteLocked)
        colour.blackAndWhiteToggle = true
        #expect(colour.customization.blackAndWhite)
    }
}

// MARK: - v2 F2 / F3: gesture mapping

@MainActor
struct CameraControlMappingTests {

    @Test func draggingUpBrightensAndDraggingDownDarkens() {
        // Negative translation.height is upward: swipe up = more light
        let brighter = CameraViewModel.exposureBias(fromDragHeight: -Constants.Camera.exposureDragScale, base: 0)
        let darker = CameraViewModel.exposureBias(fromDragHeight: Constants.Camera.exposureDragScale, base: 0)

        #expect(brighter == 1.0)
        #expect(darker == -1.0)
    }

    @Test func exposureBiasClampsToTheConfiguredRange() {
        let farUp = CameraViewModel.exposureBias(fromDragHeight: -10_000, base: 0)
        let farDown = CameraViewModel.exposureBias(fromDragHeight: 10_000, base: 0)

        #expect(farUp == Constants.Camera.exposureBiasMax)
        #expect(farDown == Constants.Camera.exposureBiasMin)
    }

    @Test func exposureDragAccumulatesFromTheBiasAtDragStart() {
        let result = CameraViewModel.exposureBias(
            fromDragHeight: -Constants.Camera.exposureDragScale / 2,
            base: 0.5
        )

        #expect(result == 1.0)
    }

    @Test func zoomClampsToTheDeviceRange() {
        #expect(CaptureSession.clampedZoom(5, min: 1, max: 10) == 5)
        #expect(CaptureSession.clampedZoom(50, min: 1, max: 10) == 10)
        #expect(CaptureSession.clampedZoom(0.2, min: 1, max: 10) == 1)
    }

    @Test func zoomCollapsesToTheMinimumWhenTheCameraCannotZoom() {
        // Front cameras commonly report min == max
        #expect(CaptureSession.clampedZoom(4, min: 1, max: 1) == 1)
    }

    @Test func chromeCounterRotatesToTheFourCardinalOrientations() {
        #expect(CameraViewModel.rotationAngle(for: .portrait, current: .degrees(90)) == .zero)
        #expect(CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: .zero) == .degrees(180))
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .zero) == .degrees(90))
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .zero) == .degrees(-90))
    }

    @Test func chromeRotationTakesTheShortArcBetweenLandscapes() {
        let a = CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(90))
        #expect(abs(a.degrees - 90) == 180)
        // 270 is the same pose as -90: no animation
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(270)) == .degrees(270))
    }

    @Test func chromeRotationAccumulatesWithoutWrapping() {
        var angle = Angle.zero
        angle = CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: angle)
        #expect(angle.degrees == 180)
        angle = CameraViewModel.rotationAngle(for: .landscapeLeft, current: angle)
        #expect(angle.degrees == 90)   // 180 -> 90, delta -90
        angle = CameraViewModel.rotationAngle(for: .portrait, current: angle)
        #expect(angle.degrees == 0)
    }

    @Test func chromeRotationEveryStepIsAtMost180() {
        let all: [UIDeviceOrientation] = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        for from in all {
            for to in all {
                let start = CameraViewModel.rotationAngle(for: from, current: .zero)
                let end = CameraViewModel.rotationAngle(for: to, current: start)
                #expect(abs(end.degrees - start.degrees) <= 180)
            }
        }
    }

    @Test func chromeRotationDoesNotDriftOnRepeatedOrientation() {
        var angle = Angle.zero
        for _ in 0..<10 {
            angle = CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: angle)
            angle = CameraViewModel.rotationAngle(for: .portrait, current: angle)
        }
        // Tie direction is consistent (+180 each way), so it accumulates in
        // whole turns but never drifts off a cardinal pose
        #expect(angle.degrees.truncatingRemainder(dividingBy: 360) == 0)
        let held = CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(90))
        #expect(held == .degrees(90))
    }

    @Test func chromeRotationHoldsLastKnownAngleOnFaceUpOrDown() {
        let held = Angle.degrees(-90)
        #expect(CameraViewModel.rotationAngle(for: .faceUp, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .faceDown, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .unknown, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(720)) == .degrees(810))
    }
}

// MARK: - v3 F3: collapsible white balance

struct WhiteBalanceVisibilityTests {

    @Test func everyWhiteBalanceModeHasASymbolName() {
        for mode in WBMode.allCases { #expect(!mode.symbolName.isEmpty) }
    }

    @Test func collapsedShowsExactlyTheSelectedMode() {
        for mode in WBMode.allCases {
            #expect(CameraViewModel.visibleModes(expanded: false, selected: mode) == [mode])
        }
    }

    @Test func expandedShowsAllModesInDeclarationOrder() {
        #expect(CameraViewModel.visibleModes(expanded: true, selected: .cloudy) == WBMode.allCases)
    }

    @Test func selectedModeIsPresentInBothStates() {
        for mode in WBMode.allCases {
            #expect(CameraViewModel.visibleModes(expanded: false, selected: mode).contains(mode))
            #expect(CameraViewModel.visibleModes(expanded: true, selected: mode).contains(mode))
        }
    }
}

// MARK: - v3 F5/F6: first-run walkthrough

struct OnboardingSequencingTests {

    // A fresh view model with the walkthrough running from step one; never
    // started against a ModelContext, so persistence is inert in these tests
    private func runningViewModel() -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.reset()
        return viewModel
    }

    @Test func advancingThroughAllThreeStepsCompletesExactlyOnce() {
        let viewModel = runningViewModel()
        #expect(viewModel.step == .library)
        viewModel.advance()
        #expect(viewModel.step == .camera)
        viewModel.advance()
        #expect(viewModel.step == .settings)
        #expect(!viewModel.hasCompleted)
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
        // Advancing past the end must not re-complete or revive a step
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
    }

    @Test func skipCompletesImmediatelyFromEveryStep() {
        for step in CoachStep.allCases {
            let viewModel = runningViewModel()
            for _ in 0..<step.rawValue { viewModel.advance() }
            #expect(viewModel.step == step)
            viewModel.skip()
            #expect(viewModel.step == nil)
            #expect(viewModel.hasCompleted)
        }
    }

    @Test func resetReturnsToTheFirstStepAndClearsCompletion() {
        let viewModel = runningViewModel()
        viewModel.skip()
        viewModel.reset()
        #expect(viewModel.step == .library)
        #expect(!viewModel.hasCompleted)
    }

    @Test func shouldPresentRequiresAllThreeGates() {
        #expect(OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: true, permissionResolved: true, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: false, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: false))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: false))
    }

    @Test func onboardingPortraitGateHoldsOnFlatOrientations() {
        #expect(OnboardingViewModel.isPortrait(for: .portraitUpsideDown, current: false))
        #expect(!OnboardingViewModel.isPortrait(for: .landscapeLeft, current: true))
        #expect(!OnboardingViewModel.isPortrait(for: .landscapeRight, current: true))
        #expect(!OnboardingViewModel.isPortrait(for: .faceUp, current: false))
        #expect(OnboardingViewModel.isPortrait(for: .unknown, current: true))
    }

    @Test func stepOrderIsLibraryCameraSettings() {
        #expect(CoachStep.library.next == .camera)
        #expect(CoachStep.camera.next == .settings)
        #expect(CoachStep.settings.next == nil)
    }

    // Completion must survive a relaunch: a second view model loading from
    // the same store starts completed, and replay clears it again (F6)
    @Test func completionPersistsAcrossViewModelLifetimes() throws {
        let container = try ModelContainer(
            for: OnboardingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = OnboardingViewModel()
        first.start(context: context)
        first.reset()
        first.skip()
        #expect(first.hasCompleted)

        let relaunched = OnboardingViewModel()
        relaunched.start(context: context)
        #expect(relaunched.hasCompleted)
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: relaunched.hasCompleted, permissionResolved: true, isPortrait: true))

        relaunched.replayWalkthrough()
        #expect(relaunched.step == .library)
        #expect(relaunched.selectedTab == .camera)

        let afterReplay = OnboardingViewModel()
        afterReplay.start(context: context)
        #expect(!afterReplay.hasCompleted)
    }

    // Catches a step being added without copy
    @Test func everyStepHasCopy() {
        for step in CoachStep.allCases {
            let entry = CoachCopy.entries[step]
            #expect(entry != nil)
            #expect(entry?.title.isEmpty == false)
            #expect(entry?.body.isEmpty == false)
        }
    }
}

// MARK: - v2 F8b: typewriter

struct TypewriterTextTests {

    @Test func revealsEveryCharacterInOrder() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("hello", interval: 0.001) { frames.append($0) }

        #expect(frames == ["h", "he", "hel", "hell", "hello"])
    }

    @Test func emptyTextProducesNoFrames() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("", interval: 0.001) { frames.append($0) }

        #expect(frames.isEmpty)
    }
}

struct PromptSelectionTests {

    @Test func neverRepeatsThePreviousPromptImmediately() {
        var last: Int? = nil
        for _ in 0..<500 {
            let next = DiaryViewModel.nextPromptIndex(excluding: last, count: PromptBank.all.count)
            #expect(next != last)
            #expect((0..<PromptBank.all.count).contains(next))
            last = next
        }
    }

    @Test func singlePromptBankAlwaysReturnsTheOnlyIndex() {
        let index = DiaryViewModel.nextPromptIndex(excluding: 0, count: 1)

        #expect(index == 0)
    }

    @Test func promptBankMeetsMinimumSize() {
        // project.md §11 requires at least 50 prompts
        #expect(PromptBank.all.count >= 50)
    }
}

// MARK: - v4 F11: per-photo stock

struct PerPhotoStockModelTests {

    @Test func diaryEntryRoundTripsItsStock() throws {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R", filmStock: .cine500T))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(fetched.first?.filmStock == .cine500T)
        #expect(fetched.first?.filmStockRaw == "cine500T")
    }

    // A row written before F11 has no stored stock: it reads as Off
    @Test func anEntryWithoutAStoredStockReadsAsOff() {
        let entry = DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R")
        #expect(entry.filmStock == .none)
        entry.filmStockRaw = nil
        #expect(entry.filmStock == .none)
        entry.filmStockRaw = "iso400"
        #expect(entry.filmStock == .portrait400, "stored stocks migrate like every other stored stock")
    }

    @MainActor
    @Test func photoboothShotsCarryTheirStockIntoTheStrip() {
        let viewModel = PhotoboothViewModel()
        let photo = solidImage(.gray)
        viewModel.add(photo, filmStock: .slide100)
        viewModel.add(photo)

        #expect(viewModel.shot(at: 0)?.filmStock == .slide100)
        #expect(viewModel.image(at: 0) === photo, "the original photo is kept, not a filtered copy")
        #expect(viewModel.stripItems.map(\.filmStock) == [.slide100, .none])
    }
}

// MARK: - v4 F12: As shot and the strip-wide override

struct StripStockOverrideTests {

    private typealias FilmStock = StripCustomization.FilmStock

    private static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// The centre pixel of slot `index` in a rendered strip.
    private func slotCentre(_ buffer: PixelBuffer, _ index: Int) -> (r: Double, g: Double, b: Double) {
        let rect = StripGenerator.Layout().photoRect(at: index)
        let scale = Constants.Strip.renderScale
        return buffer.rgb(x: Int(rect.midX * scale), y: Int(rect.midY * scale))
    }

    private func render(_ stocks: [FilmStock], override: FilmStock?) -> UIImage {
        let photo = solidImage(UIColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        var customization = StripCustomization()
        customization.filmStock = override
        let cells = stocks.map { StripGenerator.Cell(image: photo, caption: "", filmStock: $0) }
        return StripGenerator.render(strip: cells, customization: customization, date: Self.date)
    }

    private func isNeutral(_ pixel: (r: Double, g: Double, b: Double)) -> Bool {
        max(pixel.r, pixel.g, pixel.b) - min(pixel.r, pixel.g, pixel.b) < 12
    }

    @Test func newStripsDefaultToAsShot() {
        #expect(StripCustomization().filmStock == nil)
        #expect(StripCustomization.stockChoices.first == .some(nil))
        #expect(StripCustomization.stockChoices.count == FilmStock.allCases.count + 1)
        #expect(StripCustomization.label(forStockChoice: nil) == "As shot")
        #expect(StripCustomization.label(forStockChoice: .cine500T) == "Cine 500T")
    }

    @Test func asShotRendersEachFrameWithItsOwnStock() throws {
        let buffer = try #require(PixelBuffer(render([.none, .mono400, .none, .mono400], override: nil)))
        let off = slotCentre(buffer, 0)
        #expect(off.r - off.b > 80, "an Off frame keeps its colour: \(off)")
        #expect(isNeutral(slotCentre(buffer, 1)), "a Mono 400 frame renders B&W: \(slotCentre(buffer, 1))")
        #expect(slotCentre(buffer, 2) == off)
        #expect(isNeutral(slotCentre(buffer, 3)))
    }

    @Test func anOverrideReplacesEveryFramesStock() throws {
        let mono = try #require(PixelBuffer(render([.none, .daylight200, .cine500T, .slide100], override: .mono400)))
        for index in 0..<Constants.entriesPerStrip {
            #expect(isNeutral(slotCentre(mono, index)), "frame \(index) under a Mono 400 override")
        }
        let off = try #require(PixelBuffer(render([.mono400, .mono3200, .mono400, .mono400], override: FilmStock.none)))
        for index in 0..<Constants.entriesPerStrip {
            let pixel = slotCentre(off, index)
            #expect(pixel.r - pixel.b > 80, "frame \(index) under an Off override keeps its colour: \(pixel)")
        }
    }

    // Seeds stay per global frame index, so As shot over frames that share
    // a stock is byte-identical to overriding them with that stock
    @Test func asShotOverOneStockMatchesThatOverrideExactly() throws {
        let asShot = try #require(render(Array(repeating: .portrait400, count: 4), override: nil).pngData())
        let override = try #require(render(Array(repeating: .portrait400, count: 4), override: .portrait400).pngData())
        #expect(asShot == override)
    }

    @Test func asShotFramesUseTheirOwnStocksDefaultPrint() {
        var customization = StripCustomization()
        customization.printStock = .matte
        let frame = customization.effective(forFrameStock: .cine500T)
        #expect(frame.filmStock == .cine500T)
        #expect(frame.resolvedPrint == .cinema, "a strip print choice never applies to as-shot frames")

        customization.filmStock = .daylight200
        #expect(customization.effective(forFrameStock: .cine500T) == customization)
        #expect(customization.resolvedPrint == .matte)
    }

    @Test func effectsHideOnlyWhenEveryEffectiveStockIsOff() {
        typealias VM = StripViewModel
        #expect(VM.areEffectsVisible(override: nil, frameStocks: [.none, .cine500T]))
        #expect(!VM.areEffectsVisible(override: nil, frameStocks: [.none, .none]))
        #expect(!VM.areEffectsVisible(override: nil, frameStocks: []))
        #expect(!VM.areEffectsVisible(override: FilmStock.none, frameStocks: [.cine500T]))
        #expect(VM.areEffectsVisible(override: .slide100, frameStocks: [.none]))
    }

    @MainActor
    @Test func printPickerShowsOnlyForAnOverrideWithAPrintChoice() {
        let items = [StripItem(image: nil, caption: "", entryID: nil, filmStock: .cine500T)]
        let viewModel = StripViewModel(items: items, isPhotobooth: true)
        viewModel.customization = StripCustomization()
        #expect(!viewModel.isPrintPickerVisible, "As shot has no strip print")
        #expect(viewModel.availablePrints.isEmpty)
        #expect(viewModel.areEffectsVisible, "a Cine 500T frame renders effects")
        #expect(!viewModel.isBlackAndWhiteLocked)

        viewModel.customization.filmStock = .portrait400
        #expect(viewModel.isPrintPickerVisible)
        viewModel.customization.filmStock = FilmStock.none
        #expect(!viewModel.areEffectsVisible)
    }
}

// MARK: - v4 F12: Settings stock default

struct StripStockDefaultMigrationTests {

    private func scratchDefaults() throws -> UserDefaults {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let key = Constants.DefaultsKeys.stripFilmStock

    @Test func aFreshInstallDefaultsToAsShot() throws {
        let defaults = try scratchDefaults()
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func storedV4StocksStayOverrides() throws {
        let defaults = try scratchDefaults()
        for stock in StripCustomization.FilmStock.allCases {
            defaults.set(stock.rawValue, forKey: key)
            StripViewModel.migrateLegacyDefaults(defaults)
            #expect(StripViewModel.loadDefaults(from: defaults).filmStock == stock, "\(stock.label)")
            #expect(defaults.string(forKey: key) == stock.rawValue)
        }
    }

    @Test func asShotRoundTripsThroughItsStoredValue() throws {
        let defaults = try scratchDefaults()
        var customization = StripCustomization()
        customization.filmStock = .cine500T
        StripViewModel.storeDefaults(customization, in: defaults)
        customization.filmStock = nil
        StripViewModel.storeDefaults(customization, in: defaults)

        #expect(defaults.string(forKey: key) == Constants.Strip.asShotStoredValue)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(defaults.string(forKey: key) == Constants.Strip.asShotStoredValue, "migration leaves As shot alone")
    }

    // Stored As shot wins over a leftover pre-v2 grain key
    @Test func asShotIsNotOverriddenByTheLegacyGrainKey() throws {
        let defaults = try scratchDefaults()
        defaults.set(true, forKey: Constants.DefaultsKeys.stripFilmGrain)
        defaults.set(Constants.Strip.asShotStoredValue, forKey: key)
        StripViewModel.migrateLegacyDefaults(defaults)
        #expect(StripViewModel.loadDefaults(from: defaults).filmStock == nil)
    }

    @Test func storedValueMappingIsTotal() {
        #expect(StripCustomization.stockChoice(fromStoredValue: nil) == nil)
        #expect(StripCustomization.stockChoice(fromStoredValue: "asShot") == nil)
        #expect(StripCustomization.stockChoice(fromStoredValue: "iso3200") == .cine500T)
        #expect(StripCustomization.stockChoice(fromStoredValue: "bogus") == StripCustomization.FilmStock.none)
        for choice in StripCustomization.stockChoices {
            let stored = StripCustomization.storedValue(forStockChoice: choice)
            #expect(StripCustomization.stockChoice(fromStoredValue: stored) == choice)
        }
    }
}

// MARK: - v4 F9: camera film stock control

@MainActor
struct CameraFilmStockTests {

    private func scratchDefaults() throws -> UserDefaults {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func chipCodesMatchTheSpec() {
        #expect(StripCustomization.FilmStock.allCases.map(\.shortCode) == [
            "OFF", "D200", "P400", "C500", "S100", "M400", "M3.2K",
        ])
    }

    @Test func stockDefaultsToOffAndPersistsSeparatelyFromTheStrip() throws {
        let defaults = try scratchDefaults()
        let camera = CameraViewModel(defaults: defaults)
        #expect(camera.filmStock == .none)

        camera.selectFilmStock(.cine500T)
        #expect(CameraViewModel(defaults: defaults).filmStock == .cine500T)
        #expect(CameraViewModel.storedFilmStock(in: defaults) == .cine500T)
        #expect(defaults.object(forKey: Constants.DefaultsKeys.stripFilmStock) == nil, "OPEN v4-10: not shared")

        defaults.set("bogus", forKey: Constants.DefaultsKeys.cameraFilmStock)
        #expect(CameraViewModel(defaults: defaults).filmStock == .none)
    }

    @Test func openingOneListCollapsesTheOther() throws {
        let camera = CameraViewModel(defaults: try scratchDefaults())
        camera.toggleWhiteBalanceExpansion()
        camera.toggleFilmStockExpansion()
        #expect(camera.isFilmStockExpanded && !camera.isWhiteBalanceExpanded)
        camera.toggleWhiteBalanceExpansion()
        #expect(camera.isWhiteBalanceExpanded && !camera.isFilmStockExpanded)

        camera.toggleWhiteBalanceExpansion()
        camera.toggleFilmStockExpansion()
        camera.selectFilmStock(.slide100)
        #expect(!camera.isFilmStockExpanded, "a selection always collapses the list")

        camera.toggleFilmStockExpansion()
        camera.userTapped(at: .zero)
        #expect(!camera.isFilmStockExpanded, "tapping the viewfinder collapses it")
    }

    @Test func collapsedShowsTheSelectedStockAndExpandedShowsAll() {
        #expect(CameraViewModel.visibleStocks(expanded: false, selected: .mono400) == [.mono400])
        #expect(CameraViewModel.visibleStocks(expanded: true, selected: .mono400)
            == StripCustomization.FilmStock.allCases)
    }

    @Test func aCaptureShotKeepsItsStockInThePhotobooth() {
        let photobooth = PhotoboothViewModel()
        photobooth.add(PhotoboothShot(image: solidImage(.gray), filmStock: .mono3200))
        #expect(photobooth.stripItems.map(\.filmStock) == [.mono3200])
    }
}

// MARK: - v4 F13: full-resolution film look

struct FullLookRenderTests {

    private typealias FilmStock = StripCustomization.FilmStock

    /// 128×64 sensor pixels, red left / blue right, tagged like a capture.
    private func capture(_ orientation: UIImage.Orientation) -> UIImage {
        let pixels = solidImage(.red, size: CGSize(width: 128, height: 64))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64), format: format).image { context in
            pixels.draw(at: .zero)
            UIColor.blue.setFill()
            context.fill(CGRect(x: 64, y: 0, width: 64, height: 64))
        }
        return UIImage(cgImage: image.cgImage!, scale: 1, orientation: orientation)
    }

    @Test(arguments: [StripCustomization.FilmStock.daylight200, .cine500T, .mono3200])
    func fullLookKeepsTheSourceSizeAndOrientation(stock: StripCustomization.FilmStock) throws {
        let source = capture(.right)
        let look = try ImageProcessor.renderFullLook(of: source, stock: stock, seed: 7)
        let cgImage = try #require(look.cgImage)
        #expect(cgImage.width == 128 && cgImage.height == 64, "sensor pixels are not rotated")
        #expect(look.imageOrientation == .right)
        #expect(look.size == source.size)
    }

    @Test func offReturnsTheDevelopedPhotoItself() throws {
        let source = capture(.left)
        #expect(try ImageProcessor.renderFullLook(of: source, stock: .none, seed: 1) === source)
    }

    @Test func theSameSeedGivesAnIdenticalResult() throws {
        let source = capture(.up)
        let first = try #require(PixelBuffer(try ImageProcessor.renderFullLook(of: source, stock: .portrait400, seed: 42)))
        let second = try #require(PixelBuffer(try ImageProcessor.renderFullLook(of: source, stock: .portrait400, seed: 42)))
        #expect(first == second)
    }

    @Test func aCoveringSizeShrinksInUprightTerms() throws {
        // .right-tagged 128×64 sensor = 64×128 upright; covering 32×32
        // upright needs 32×64 upright = 64×32 sensor
        let look = try ImageProcessor.renderFullLook(
            of: capture(.right), stock: .slide100, seed: 1, coveringPixelSize: CGSize(width: 32, height: 32)
        )
        let cgImage = try #require(look.cgImage)
        #expect(cgImage.width == 64 && cgImage.height == 32)
        #expect(look.imageOrientation == .right)
    }

    // The review screen must show what Download saves: grain is sized to
    // the frame, so the full render scaled down to review size has about
    // the review render's grain. ±35% allows for the two resampling paths
    // (Lanczos before the look vs. drawing the full render down after it).
    @Test func downloadGrainMatchesTheReviewRenderAtReviewSize() throws {
        let reviewWidth = Constants.ImageProcessing.Film.grainReferenceWidth
        let review = CGSize(width: reviewWidth, height: reviewWidth * 0.75)
        let source = solidImage(UIColor(white: 0.25, alpha: 1), size: CGSize(width: review.width * 2, height: review.height * 2))

        let full = try ImageProcessor.renderFullLook(of: source, stock: .mono3200, seed: 9)
        let screen = try ImageProcessor.renderFullLook(of: source, stock: .mono3200, seed: 9, coveringPixelSize: review)
        #expect(screen.cgImage?.width == Int(review.width))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let downsampled = UIGraphicsImageRenderer(size: review, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            full.draw(in: CGRect(origin: .zero, size: review))
        }
        let fullVariance = try #require(PixelBuffer(downsampled)).luminanceVariance
        let screenVariance = try #require(PixelBuffer(screen)).luminanceVariance
        #expect(screenVariance > 1, "the review render has grain")
        let ratio = fullVariance / screenVariance
        #expect(ratio > 0.65 && ratio < 1.35, "downsampled Download grain variance \(fullVariance) vs review \(screenVariance)")
    }

    @Test func heicKeepsPixelsSizeAndOrientationTag() throws {
        let data = try ImageProcessor.heicData(from: capture(.right))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.heic")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 128)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 64)
        #expect(properties[kCGImagePropertyOrientation] as? UInt32 == CGImagePropertyOrientation.right.rawValue)
    }
}

// MARK: - v4 F10 / F13: diary review state

/// Thread-safe record of what Download saved, standing in for the camera roll.
private final class SavedPhotos: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data] = []
    var all: [Data] { lock.withLock { stored } }
    func save(_ data: Data) { lock.withLock { stored.append(data) } }
}

@MainActor
struct DiaryReviewStateTests {

    private func pixelSize(of data: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    @Test func offShowsTheOriginalWithoutRendering() {
        let preview = solidImage(.gray)
        let review = DiaryReviewViewModel(preview: preview, stock: .none)
        #expect(review.renderedPhoto === preview)
        #expect(!review.isRendering)
        #expect(review.stockChoices == StripCustomization.FilmStock.allCases)
    }

    @Test func quickStockTapsRenderOnlyTheLast() async throws {
        let review = DiaryReviewViewModel(preview: solidImage(.gray), stock: .none)
        review.setDisplaySize(CGSize(width: 16, height: 16), scale: 2)
        review.selectStock(.daylight200)
        review.selectStock(.cine500T)
        review.selectStock(.mono400)
        #expect(review.isRendering)
        #expect(review.isDownloadDisabled, "Download waits for the render")
        await review.renderSettled()

        #expect(review.stock == .mono400)
        #expect(!review.isRendering)
        let rendered = try #require(review.renderedPhoto.flatMap(PixelBuffer.init))
        let centre = rendered.rgb(x: rendered.width / 2, y: rendered.height / 2)
        #expect(abs(centre.r - centre.b) < 6, "the Mono 400 render won: \(centre)")
        #expect(rendered.width == 32, "rendered at display size, not source size")
    }

    @Test func theDevelopedRAWReplacesThePreview() async {
        let preview = solidImage(.gray)
        let developed = solidImage(.white, size: CGSize(width: 96, height: 96))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let review = DiaryReviewViewModel(preview: preview, stock: .none, development: development)
        #expect(review.photo === preview && review.isDevelopingPhoto)

        continuation.yield(developed)
        let final = await review.developedPhoto()
        await Task.yield()
        #expect(final === developed)
        #expect(review.photo === developed)
        #expect(!review.isDevelopingPhoto)
        #expect(review.renderedPhoto === developed, "Off shows the new original")
    }

    @Test func downloadWaitsForTheRAWAndSavesFullResolution() async throws {
        let preview = solidImage(.gray, size: CGSize(width: 32, height: 24))
        let developed = solidImage(.gray, size: CGSize(width: 160, height: 120))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let saved = SavedPhotos()
        let review = DiaryReviewViewModel(
            preview: preview, stock: .portrait400, development: development, savePhotoData: { saved.save($0) }
        )
        review.setDisplaySize(CGSize(width: 10, height: 10), scale: 1)

        let download = Task { await review.downloadReview() }
        await Task.yield()
        #expect(review.isSavingDownload)
        continuation.yield(developed)
        await download.value

        #expect(saved.all.count == 1)
        #expect(pixelSize(of: try #require(saved.all.first)) == CGSize(width: 160, height: 120),
                "the developed RAW at full size, never the preview or the display render")
        #expect(review.didSaveDownload)
        #expect(!review.isSavingDownload)

        // OPEN v4-15 default: a second tap saves a second photo
        await review.downloadReview()
        #expect(saved.all.count == 2)
    }

    @Test func aFailedSaveRaisesAnErrorAndShowsNoSavedState() async {
        let errors = ErrorState()
        let review = DiaryReviewViewModel(
            preview: solidImage(.gray), stock: .none,
            savePhotoData: { _ in throw AppError.photoLibraryPermissionDenied }
        )
        review.errorState = errors
        await review.downloadReview()
        #expect(!review.didSaveDownload)
        if case .photoLibraryPermissionDenied = errors.current {} else {
            Issue.record("expected the permission error, got \(String(describing: errors.current))")
        }
    }

    @Test func okCarriesTheChosenStockToTheEditorAndRetakeDropsTheCapture() throws {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let camera = CameraViewModel(defaults: defaults)
        camera.selectFilmStock(.daylight200)

        let preview = solidImage(.gray)
        camera.beginReview(preview: preview, stock: camera.filmStock)
        let review = try #require(camera.review)
        #expect(review.stock == .daylight200, "the review starts from the camera's stock")
        review.selectStock(.slide100)

        camera.confirmReview()
        #expect(camera.isEditorPresented && !camera.isReviewPresented)
        #expect(camera.pendingDiaryStock == .slide100)
        #expect(camera.pendingDiaryImage === preview, "the original is what gets saved")
        #expect(camera.filmStock == .daylight200, "changing the review stock leaves the camera's alone")

        camera.retake()
        #expect(camera.review == nil && camera.pendingDiaryImage == nil)
        #expect(!camera.isEditorPresented && !camera.isReviewPresented)
        #expect(camera.pendingDiaryStock == .none)
    }

    @Test func savingAnEntryStoresTheReviewedStock() throws {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(image: solidImage(.gray), filmStock: .cine500T, includeText: false, context: context))
        let entry = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        #expect(entry.filmStock == .cine500T)
        try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath))
    }
}

// MARK: - v4 F11: display in the entry's stock

struct FilmLookCacheTests {

    @Test func aCacheHitReturnsTheIdenticalImageWithoutReloading() {
        let cache = FilmLookCache()
        let id = UUID()
        var loads = 0
        let load: () -> UIImage? = { loads += 1; return solidImage(.gray, size: CGSize(width: 80, height: 60)) }
        let size = CGSize(width: 40, height: 30)

        let first = cache.image(id: id, stock: .cine500T, seed: 3, pixelSize: size, loadPhoto: load)
        let second = cache.image(id: id, stock: .cine500T, seed: 3, pixelSize: size, loadPhoto: load)
        #expect(first != nil && first === second)
        #expect(loads == 1)
        #expect(cache.cachedImage(id: id, stock: .cine500T, pixelSize: size) === first)

        // Another stock or size is another entry in the cache
        _ = cache.image(id: id, stock: .mono400, seed: 3, pixelSize: size, loadPhoto: load)
        _ = cache.image(id: id, stock: .cine500T, seed: 3, pixelSize: CGSize(width: 20, height: 15), loadPhoto: load)
        #expect(loads == 3)
    }

    @Test func offReturnsTheOriginal() {
        let photo = solidImage(.gray)
        let shown = FilmLookCache().image(id: UUID(), stock: .none, seed: 0, pixelSize: CGSize(width: 8, height: 8)) { photo }
        #expect(shown === photo)
    }

    @Test func aRenderIsSizedToCoverTheView() throws {
        let shown = FilmLookCache().image(
            id: UUID(), stock: .portrait400, seed: 0, pixelSize: CGSize(width: 40, height: 40)
        ) { solidImage(.gray, size: CGSize(width: 200, height: 100)) }
        let cgImage = try #require(shown?.cgImage)
        #expect(cgImage.width == 80 && cgImage.height == 40)
    }

    @Test func aMissingPhotoIsNil() {
        #expect(FilmLookCache().image(id: UUID(), stock: .slide100, seed: 0, pixelSize: CGSize(width: 8, height: 8)) { nil } == nil)
    }
}

// MARK: - v4 F9: live film preview

struct FilmPreviewMappingTests {

    /// AVFoundation's own fit math: the part of the frame an aspect-fill
    /// view shows is the largest view-shaped rect centred in the frame.
    /// Mapping that crop through `aspectFillRect` must land exactly on the
    /// view, so the film view and the preview layer (which converts taps)
    /// agree on every point.
    @Test(arguments: [
        (CGSize(width: 1080, height: 1440), CGSize(width: 402, height: 874)),   // portrait frame, tall phone
        (CGSize(width: 1440, height: 1080), CGSize(width: 402, height: 874)),   // sensor-orientation frame
        (CGSize(width: 3024, height: 4032), CGSize(width: 300, height: 400)),   // same aspect
        (CGSize(width: 1080, height: 1920), CGSize(width: 500, height: 500)),
    ])
    func aspectFillMatchesTheCropAVFoundationShows(frame: CGSize, view: CGSize) {
        let bounds = CGRect(origin: .zero, size: view)
        let fill = FilmPreviewRenderer.aspectFillRect(imageSize: frame, in: bounds)
        let crop = AVMakeRect(aspectRatio: view, insideRect: CGRect(origin: .zero, size: frame))
        let scale = fill.width / frame.width

        #expect(abs(fill.height / frame.height - scale) < 1e-9, "uniform scale")
        let mapped = CGRect(
            x: fill.minX + crop.minX * scale, y: fill.minY + crop.minY * scale,
            width: crop.width * scale, height: crop.height * scale
        )
        #expect(abs(mapped.minX - bounds.minX) < 0.5 && abs(mapped.minY - bounds.minY) < 0.5)
        #expect(abs(mapped.width - bounds.width) < 0.5 && abs(mapped.height - bounds.height) < 0.5)
    }

    @Test func thePreviewUsesTheStripsCubeForEachStock() {
        #expect(FilmPreviewRenderer.previewCube(for: .none) == nil)
        for stock in StripCustomization.FilmStock.allCases where stock != .none {
            let negative = stock.negative!
            let print = stock.defaultPrint!.profile
            #expect(FilmPreviewRenderer.previewCube(for: stock)
                == FilmLUT.cachedCube(negative: negative, print: print, monochrome: stock.isMonochrome), "\(stock.label)")
        }
    }

    @Test func offPassesTheFrameThroughAndAStockChangesIt() throws {
        let frame = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 12, height: 16))
        let size = CGSize(width: 6, height: 8)
        let context = CIContext()
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        func centre(_ image: CIImage) -> [UInt8] {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 3, y: 4, width: 1, height: 1),
                           format: .RGBA8, colorSpace: space)
            return pixel
        }
        let off = FilmPreviewRenderer.previewImage(frame, cube: nil, drawableSize: size)
        #expect(off.extent == CGRect(origin: .zero, size: size))
        let original = centre(off)
        #expect(abs(Int(original[0]) - 204) <= 2 && abs(Int(original[1]) - 77) <= 2)

        let mono = FilmPreviewRenderer.previewImage(
            frame, cube: FilmPreviewRenderer.previewCube(for: .mono400), drawableSize: size
        )
        let grey = centre(mono)
        #expect(abs(Int(grey[0]) - Int(grey[2])) <= 3, "Mono 400 renders neutral: \(grey)")
    }

    // Core Image's origin is bottom-left and a screen's is top-left: the
    // top of the frame must reach the top row of the drawable
    @MainActor
    @Test func theFrameRendersUprightIntoAMetalTexture() throws {
        let renderer = FilmPreviewRenderer()
        let device = try #require(renderer.device, "the simulator and every supported phone have Metal")
        let queue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let commandBuffer = try #require(queue.makeCommandBuffer())

        // Red in Core Image's upper half (high y), blue in the lower half
        let top = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 4, width: 8, height: 4))
        let bottom = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))
        try renderer.render(top.composited(over: bottom), to: texture, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var row = [UInt8](repeating: 0, count: 8 * 4)
        texture.getBytes(&row, bytesPerRow: 8 * 4, from: MTLRegionMake2D(0, 0, 8, 1), mipmapLevel: 0)
        // BGRA: red is byte 2, blue byte 0
        #expect(row[2] > 200 && row[0] < 50, "top texture row should be red, got B\(row[0]) R\(row[2])")
    }

    @MainActor
    @Test func theFilmViewfinderShowsOnlyWithAStock() throws {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let camera = CameraViewModel(defaults: defaults)
        #expect(!camera.showsFilmPreview && !camera.filmPreviewRenderer.isActive)
        camera.selectFilmStock(.cine500T)
        #expect(camera.showsFilmPreview && camera.filmPreviewRenderer.isActive)
    }
}

// MARK: - OBS-V4-7: the diary shows the grain the review showed

@MainActor
struct EntryLookSeedTests {

    @Test func anEntrySavedFromAReviewRendersTheReviewsGrain() async throws {
        let photo = solidImage(UIColor(white: 0.4, alpha: 1), size: CGSize(width: 120, height: 90))
        let captureDate = Date(timeIntervalSince1970: 1_790_000_123)
        let review = DiaryReviewViewModel(preview: photo, stock: .mono3200, captureDate: captureDate)
        review.setDisplaySize(CGSize(width: 60, height: 45), scale: 1)
        await review.renderSettled()
        let reviewed = try #require(review.renderedPhoto.flatMap(PixelBuffer.init))

        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(
            image: photo, filmStock: review.stock, capturedAt: review.captureDate, includeText: false, context: context
        ))
        let entry = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }
        #expect(entry.capturedAt == captureDate)
        #expect(entry.lookSeedDate == captureDate, "seeded from the capture, not the save")

        let shown = FilmLookCache().image(
            id: entry.id, stock: entry.filmStock,
            seed: StripGenerator.photoLookSeed(for: entry.lookSeedDate),
            pixelSize: CGSize(width: 60, height: 45)
        ) { photo }
        #expect(try #require(shown.flatMap(PixelBuffer.init)) == reviewed, "same grain as the review")
    }

    @Test func entriesFromBeforeTheCaptureDateFallBackToCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = DiaryEntry(createdAt: created, photoPath: "Photos/a.jpg", prompt: "P", response: "R")
        #expect(entry.capturedAt == nil)
        #expect(entry.lookSeedDate == created)
    }

    @Test func entryStockIsReadOnlyInV4() {
        #expect(!Constants.Diary.entryStockIsEditable)
        #expect(Constants.Camera.galleryPicksUseCameraStock)
    }
}
