import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// ImageProcessor: strip look, full-frame look, FilmLookCache, live film preview.

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
    // The two enums share case names but not raw values: bridging through
    // rawValue would silently turn .right into .downMirrored. Each case also
    // round-trips back to the same EXIF value.
    @Test(arguments: [
        (CGImagePropertyOrientation.up, UIImage.Orientation.up),
        (.upMirrored, .upMirrored),
        (.down, .down),
        (.downMirrored, .downMirrored),
        (.leftMirrored, .leftMirrored),
        (.right, .right),
        (.rightMirrored, .rightMirrored),
        (.left, .left),
    ])
    func exifOrientationMapsToTheMatchingUIImageOrientationAndBack(exif: CGImagePropertyOrientation, ui: UIImage.Orientation) {
        #expect(ImageProcessor.uiOrientation(from: exif) == ui)
        #expect(ImageProcessor.cgOrientation(from: ui) == exif)
    }

    // The four upright quarter-turns must stay distinct: collapsing any two
    // is what a sign-convention slip looks like, and it would rotate every
    // landscape capture the wrong way rather than failing loudly.
    @Test func theFourQuarterTurnsAreDistinct() {
        let quarterTurns: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let mapped = quarterTurns.map(ImageProcessor.uiOrientation(from:))
        #expect(Set(mapped.map(\.rawValue)).count == quarterTurns.count)
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
        let defaults = try makeScratchDefaults()
        let camera = CameraViewModel(defaults: defaults)
        #expect(!camera.showsFilmPreview && !camera.filmPreviewRenderer.isActive)
        camera.selectFilmStock(.cine500T)
        #expect(camera.showsFilmPreview && camera.filmPreviewRenderer.isActive)
    }
}
