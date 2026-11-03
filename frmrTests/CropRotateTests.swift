import Testing
import UIKit
@testable import frmr

// F-122-F follow-ups: the orientation swap on every preset but 1:1, Rotate 90
// (stored as FilmLook.quarterTurns, so strips honour it) and the stand-in
// that replaces the flash when the Crop tool is left.

private let landscapeSize = CGSize(width: 96, height: 72)
private let portraitSize = CGSize(width: 72, height: 96)

private func pixelRatio(_ rect: CGRect, in size: CGSize) -> CGFloat {
    (rect.width * size.width) / (rect.height * size.height)
}

/// Top-left red, top-right green, bottom-left blue, bottom-right white, in
/// sensor space, tagged `orientation`.
private func quadrants(_ size: CGSize, orientation: UIImage.Orientation = .up) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let half = CGSize(width: size.width / 2, height: size.height / 2)
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(origin: .zero, size: half))
        UIColor.green.setFill()
        context.fill(CGRect(x: half.width, y: 0, width: half.width, height: half.height))
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: half.height, width: half.width, height: half.height))
        UIColor.white.setFill()
        context.fill(CGRect(x: half.width, y: half.height, width: half.width, height: half.height))
    }
    guard let cgImage = image.cgImage else { return image }
    return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
}

/// The image as the user sees it (orientation applied), one pixel per point.
private func upright(_ image: UIImage) -> PixelBuffer? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return PixelBuffer(UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    })
}

private func dominant(_ pixel: (r: Double, g: Double, b: Double)) -> String {
    switch (pixel.r > 170, pixel.g > 170, pixel.b > 170) {
    case (true, false, false): return "red"
    case (false, true, false): return "green"
    case (false, false, true): return "blue"
    case (true, true, true): return "white"
    default: return "other"
    }
}

/// The four quadrants' colours of the upright picture: TL, TR, BL, BR.
private func corners(_ image: UIImage) -> [String] {
    guard let pixels = upright(image) else { return [] }
    let w = pixels.width, h = pixels.height
    return [(w / 4, h / 4), (3 * w / 4, h / 4), (w / 4, 3 * h / 4), (3 * w / 4, 3 * h / 4)]
        .map { dominant(pixels.rgb(x: $0.0, y: $0.1)) }
}

// MARK: - Orientation swap

@MainActor
struct CropSwapTests {

    private func edit(_ size: CGSize) -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: solidImage(.gray, size: size), stock: .portrait400)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    @Test func originalOnAPortraitPhotoBecomesTheLargestCentredLandscape() {
        let edit = edit(portraitSize)
        edit.select(tool: .crop)
        #expect(edit.canSwapCropOrientation, "the tool opens on Original and the swap is enabled")
        edit.swapCropOrientation()

        let crop = edit.cropState
        #expect(crop.preset == .original && crop.isLandscape, "still the Original chip, flipped to landscape")
        #expect(abs(pixelRatio(crop.rect, in: portraitSize) - 4.0 / 3.0) < 1e-6)
        #expect(abs(crop.rect.midX - 0.5) < 1e-9 && abs(crop.rect.midY - 0.5) < 1e-9)
        #expect(abs(crop.rect.width - 1) < 1e-9, "the largest one that fits")
        #expect(edit.cropReadout == "Original" && edit.canResetCrop)
    }

    @Test func originalOnALandscapePhotoBecomesPortraitAndSwapsBackToTheWholePhoto() {
        let edit = edit(landscapeSize)
        edit.swapCropOrientation()
        #expect(!edit.cropState.isLandscape && abs(pixelRatio(edit.cropState.rect, in: landscapeSize) - 0.75) < 1e-6)
        #expect(abs(edit.cropState.rect.height - 1) < 1e-9)

        // A resize keeps the swapped ratio
        let frame = edit.cropState.rect
        edit.resizeCrop(.bottomRight, from: frame, byPoints: CGSize(width: -10, height: -10), in: landscapeSize)
        #expect(abs(pixelRatio(edit.cropState.rect, in: landscapeSize) - 0.75) < 1e-6)

        edit.swapCropOrientation()
        #expect(edit.look.crop == nil, "back in the photo's own orientation it is the whole photo again")
    }

    @Test func aSquarePhotoOnOriginalAndAnyOneByOneCannotSwap() {
        let square = edit(CGSize(width: 64, height: 64))
        #expect(!square.canSwapCropOrientation)
        let before = square.cropState
        square.swapCropOrientation()
        #expect(square.cropState == before)

        let wide = edit(landscapeSize)
        wide.selectCropPreset(.oneByOne)
        #expect(!wide.canSwapCropOrientation)
        #expect(CropPreset.allCases.filter { !$0.canSwapOrientation } == [.oneByOne])
    }

    @Test func freeSwapsTheFramesWidthAndHeightAroundItsCentre() {
        let size = CGSize(width: 400, height: 300)
        let frame = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.2)  // 160×60 px
        let turned = CropGeometry.swapped(frame, preset: .free, toLandscape: false, imageSize: size)
        #expect(abs(turned.width * size.width - 60) < 1e-6 && abs(turned.height * size.height - 160) < 1e-6)
        #expect(abs(turned.midX - frame.midX) < 1e-9 && abs(turned.midY - frame.midY) < 1e-9)

        // Too tall for the photo: shrunk to fit, ratio kept
        let strip = CGRect(x: 0, y: 0.4, width: 1, height: 0.2)  // 400×60 px
        let fitted = CropGeometry.swapped(strip, preset: .free, toLandscape: false, imageSize: size)
        #expect(abs(fitted.height - 1) < 1e-9 && abs(pixelRatio(fitted, in: size) - 60.0 / 400.0) < 1e-6)
        #expect(fitted.minX >= 0 && fitted.maxX <= 1 + 1e-9)
    }

    @Test func freeSwapsInTheEditorAndFixedRatiosStillDo() {
        let edit = edit(landscapeSize)
        edit.selectCropPreset(.free)
        edit.resizeCrop(.bottomRight, from: CGRect(x: 0, y: 0, width: 1, height: 1), byPoints: CGSize(width: -48, height: -36), in: landscapeSize)
        let before = edit.cropState.rect
        #expect(edit.canSwapCropOrientation)
        edit.swapCropOrientation()
        let after = edit.cropState
        #expect(after.preset == .free)
        #expect(abs(after.width * 96 - before.height * 72) < 1e-6 && abs(after.height * 72 - before.width * 96) < 1e-6)

        edit.selectCropPreset(.fourByFive)
        edit.swapCropOrientation()
        #expect(abs(pixelRatio(edit.cropState.rect, in: landscapeSize) - 0.8) < 1e-6)
        #expect(!edit.cropState.isLandscape)
    }
}

// MARK: - Rotate

struct RotateGeometryTests {

    @Test func aCropTurnsWithThePhotoAndFourTurnsComeBack() {
        let crop = CropRect(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), preset: .threeByFour, isLandscape: false)
        let turned = crop.turnedClockwise
        #expect(abs(turned.x - 0.4) < 1e-9 && abs(turned.y - 0.1) < 1e-9 && abs(turned.width - 0.4) < 1e-9 && abs(turned.height - 0.3) < 1e-9)
        #expect(turned.isLandscape && turned.preset == .threeByFour)

        let round = crop.turnedClockwise.turnedClockwise.turnedClockwise.turnedClockwise
        #expect(abs(round.x - crop.x) < 1e-9 && abs(round.y - crop.y) < 1e-9)
        #expect(abs(round.width - crop.width) < 1e-9 && abs(round.height - crop.height) < 1e-9)
        #expect(round.isLandscape == crop.isLandscape)
        #expect(CropRect.fullFrame.turnedClockwise.isFullFrame, "the whole photo stays the whole photo")
    }

    @Test(arguments: [UIImage.Orientation.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored])
    func orientationTurnsCompose(orientation: UIImage.Orientation) {
        #expect(ImageProcessor.turnedOrientation(orientation, clockwise: 0) == orientation)
        #expect(ImageProcessor.turnedOrientation(orientation, clockwise: 4) == orientation)
        #expect(ImageProcessor.turnedOrientation(orientation, clockwise: -1) == ImageProcessor.turnedOrientation(orientation, clockwise: 3))
        let once = ImageProcessor.turnedOrientation(orientation, clockwise: 1)
        #expect(ImageProcessor.turnedOrientation(once, clockwise: 1) == ImageProcessor.turnedOrientation(orientation, clockwise: 2))
    }

    @Test func zeroTurnsIsTheImageItself() {
        let image = quadrants(CGSize(width: 40, height: 20))
        #expect(ImageProcessor.turnedPhoto(image, quarterTurns: 0) === image)
        #expect(ImageProcessor.geometryOnly(image, look: .original) === image)
    }
}

struct RotateRenderTests {

    @Test(arguments: 0...3)
    func quarterTurnsSwapTheOutputDimensionsForOddTurns(turns: Int) throws {
        let source = quadrants(CGSize(width: 120, height: 80))
        for look in [FilmLook.original, .stockDefaults(for: .portrait400)] {
            let output = try ImageProcessor.renderFullLook(of: source, look: look.with(quarterTurns: turns), seed: 1)
            let expected = turns % 2 == 0 ? CGSize(width: 120, height: 80) : CGSize(width: 80, height: 120)
            #expect(output.size == expected, "\(look.stock) × \(turns)")
        }
    }

    @Test func aTurnedPhotoHasItsTopOnTheRight() throws {
        // Top-left red, top-right green, bottom-left blue, bottom-right white
        let source = quadrants(CGSize(width: 40, height: 20))
        let expected = [
            ["red", "green", "blue", "white"],
            ["blue", "red", "white", "green"],
            ["white", "blue", "green", "red"],
            ["green", "white", "red", "blue"],
        ]
        for turns in 0...3 {
            let output = try ImageProcessor.renderFullLook(of: source, look: .original.with(quarterTurns: turns), seed: 1)
            #expect(corners(output) == expected[turns], "\(turns) clockwise turns")
        }
    }

    @Test func aRedTopExifRotatedPhotoTurnsFromItsUprightSelf() throws {
        // Sensor: red left half, blue right half, tagged .right: red on top upright
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let raster = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }
        let source = UIImage(cgImage: try #require(raster.cgImage), scale: 1, orientation: .right)
        let top = try #require(upright(source))
        #expect(dominant(top.rgb(x: top.width / 2, y: 2)) == "red")

        let once = try ImageProcessor.renderFullLook(of: source, look: .original.with(quarterTurns: 1), seed: 1)
        let pixels = try #require(upright(once))
        #expect(pixels.width == 40 && pixels.height == 20)
        #expect(dominant(pixels.rgb(x: pixels.width - 3, y: pixels.height / 2)) == "red", "red top is on the right after a clockwise turn")
        #expect(dominant(pixels.rgb(x: 2, y: pixels.height / 2)) == "blue")
    }

    @Test(arguments: [UIImage.Orientation.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored], 0...3)
    func theCheapStandInMatchesTheRenderForEveryTagTurnAndCrop(orientation: UIImage.Orientation, turns: Int) throws {
        let source = quadrants(CGSize(width: 48, height: 32), orientation: orientation)
        let crop = CropRect(rect: CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.75), preset: .free)
        let look = FilmLook.original.with(crop: crop).with(quarterTurns: turns)

        let rendered = try #require(upright(try ImageProcessor.renderFullLook(of: source, look: look, seed: 1)))
        let cheap = try #require(upright(ImageProcessor.geometryOnly(source, look: look)))
        #expect(rendered.width == cheap.width && rendered.height == cheap.height)
        let worst = zip(rendered.bytes, cheap.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 12)
    }

    @Test func zeroTurnsRendersExactlyAsBefore() throws {
        let source = quadrants(CGSize(width: 64, height: 48), orientation: .right)
        let look = FilmLook.stockDefaults(for: .cine500T)
        let plain = try ImageProcessor.renderFullLook(of: source, look: look, seed: 4)
        let zero = try ImageProcessor.renderFullLook(of: source, look: look.with(quarterTurns: 0), seed: 4)
        #expect(PixelBuffer(plain) == PixelBuffer(zero) && plain.imageOrientation == zero.imageOrientation)
        #expect(FilmLook.original.with(quarterTurns: 4) == FilmLook.original)
    }

    @Test func aTurnAloneRendersWithoutAFilmLook() throws {
        let source = quadrants(CGSize(width: 40, height: 20))
        #expect(FilmLook.original.with(quarterTurns: 1).altersOutput)
        let output = try ImageProcessor.renderFullLook(of: source, look: .original.with(quarterTurns: 1), seed: 1)
        #expect(output !== source)
    }

    @Test func theCacheDecodesBigEnoughForATurnedCrop() {
        let look = FilmLook.original.with(quarterTurns: 1)
        #expect(look.sourceCoveringSize(forOutput: CGSize(width: 30, height: 60)) == CGSize(width: 60, height: 30))
        let cropped = look.with(crop: CropRect(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(cropped.sourceCoveringSize(forOutput: CGSize(width: 30, height: 60)) == CGSize(width: 120, height: 60))
        #expect(FilmLook.original.sourceCoveringSize(forOutput: CGSize(width: 30, height: 60)) == CGSize(width: 30, height: 60))
    }
}

// MARK: - Stored form and strips

struct RotateStoredFormAndStripTests {

    @Test func turnsSurviveACodableRoundTripAndOldLooksHaveNone() throws {
        let look = FilmLook.stockDefaults(for: .portrait400).with(quarterTurns: 3)
            .with(crop: CropRect(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)))
        let data = try #require(FilmLook.encoded(look))
        #expect(FilmLook.decoded(from: data) == look && FilmLook.decoded(from: data).quarterTurns == 3)

        #expect(FilmLook.decoded(from: Data(#"{"stock":"none"}"#.utf8)).quarterTurns == 0)
        let unturned = try #require(FilmLook.encoded(.stockDefaults(for: .cine500T)))
        #expect(!String(decoding: unturned, as: UTF8.self).contains("quarterTurns"))
        #expect(FilmLook.decoded(from: Data(#"{"stock":"none","quarterTurns":6}"#.utf8)).quarterTurns == 2)
        #expect(FilmLook.decoded(from: Data(#"{"stock":"none","quarterTurns":"x"}"#.utf8)).quarterTurns == 0)
    }

    @Test func turnsAreGeometryNotLook() {
        let turned = FilmLook.stockDefaults(for: .slide100).with(quarterTurns: 1)
        #expect(turned.isStockDefault)
        #expect(turned.withoutGeometry == FilmLook.stockDefaults(for: .slide100))
    }

    @Test func theStripDescriptionCarriesTheTurnsButNotTheCrop() {
        let look = FilmLook.stockDefaults(for: .portrait400).with(quarterTurns: 1)
            .with(crop: CropRect(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(look.customization.quarterTurns == 1)

        let strip = StripCustomization()
        #expect(strip.effective(forFrameStock: .portrait400, look: look).quarterTurns == 1, "as shot")
        var override = StripCustomization()
        override.filmStock = .cine500T
        #expect(override.effective(forFrameStock: .portrait400, look: look).quarterTurns == 1, "a stock override keeps the photo's turns")
        #expect(strip.effective(forFrameStock: .portrait400, look: nil).quarterTurns == 0)
    }

    @Test func aStripFrameIsTurnedUprightWithOrWithoutAFilmLook() throws {
        // Turned once clockwise: blue top-left, red top-right, white bottom-left, green bottom-right
        let photo = quadrants(CGSize(width: 120, height: 90))
        var customization = StripCustomization()
        customization.quarterTurns = 1
        let plain = ImageProcessor.applyStripLook(to: photo, customization: customization, outputWidth: 120)
        #expect(corners(plain) == ["blue", "red", "white", "green"], "no film, only the turn")

        customization.filmStock = .portrait400
        let film = try #require(upright(ImageProcessor.applyStripLook(to: photo, customization: customization, outputWidth: 120)))
        let left = film.rgb(x: film.width / 4, y: film.height / 4), right = film.rgb(x: 3 * film.width / 4, y: film.height / 4)
        #expect(left.b > left.r && right.r > right.b, "with film")
    }

    @Test func aStripRendersATurnedPhotoDifferentlyAndAZeroTurnPhotoAsBefore() {
        let photo = quadrants(CGSize(width: 120, height: 90))
        func strip(_ look: FilmLook) -> UIImage {
            let cells = (0..<Constants.entriesPerStrip).map { _ in StripGenerator.Cell(image: photo, caption: "", look: look) }
            return StripGenerator.render(strip: cells, customization: StripCustomization(), date: Date(timeIntervalSince1970: 1_000))
        }
        let plain = strip(.original)
        #expect(PixelBuffer(strip(.original.with(quarterTurns: 0))) == PixelBuffer(plain))
        #expect(PixelBuffer(strip(.original.with(quarterTurns: 1))) != PixelBuffer(plain))
        #expect(PixelBuffer(strip(.original.with(quarterTurns: 2))) != PixelBuffer(plain))
    }
}

// MARK: - Editor

@MainActor
struct RotateEditorTests {

    private func edit(_ size: CGSize = landscapeSize, stock: StripCustomization.FilmStock = .portrait400) -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: quadrants(size), stock: stock)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    @Test func rotatingTurnsThePhotoAndFourTapsComeBack() {
        let edit = edit()
        edit.select(tool: .crop)
        let start = edit.look
        edit.rotatePhoto()
        #expect(edit.look.quarterTurns == 1 && edit.canResetCrop && edit.isModified)
        #expect(edit.cropCanvasPhoto.size == portraitSize, "the canvas shows the turned photo")
        edit.rotatePhoto()
        edit.rotatePhoto()
        #expect(edit.look.quarterTurns == 3)
        edit.rotatePhoto()
        #expect(edit.look == start && !edit.canResetCrop && !edit.isModified)
    }

    @Test func rotatingWithACropKeepsTheSameRegion() throws {
        let edit = edit()
        edit.select(tool: .crop)
        edit.selectCropPreset(.free)
        // The top-left (red) quarter of the photo
        edit.resizeCrop(.bottomRight, from: CGRect(x: 0, y: 0, width: 1, height: 1), byPoints: CGSize(width: -48, height: -36), in: landscapeSize)
        let photo = edit.photo
        func region(_ look: FilmLook) throws -> String {
            let output = try ImageProcessor.renderFullLook(of: photo, look: look.with(stock: .none), seed: 1)
            return dominant(try #require(PixelBuffer(output)).channelMeans)
        }
        #expect(try region(edit.look) == "red")
        edit.rotatePhoto()
        let rect = edit.cropState.rect
        #expect(abs(rect.minX - 0.5) < 1e-9 && abs(rect.minY) < 1e-9, "red moved to the top right")
        #expect(try region(edit.look) == "red", "the same region of the photo")
        edit.rotatePhoto()
        edit.rotatePhoto()
        edit.rotatePhoto()
        #expect(try region(edit.look) == "red")
        #expect(abs(edit.cropState.rect.minX) < 1e-9 && abs(edit.cropState.rect.width - 0.5) < 1e-9)
    }

    @Test func aFixedRatioCropFlipsItsOrientationWithTheTurn() throws {
        let edit = edit()
        edit.selectCropPreset(.threeByFour)
        #expect(edit.cropState.isLandscape, "a landscape photo starts landscape")
        edit.rotatePhoto()
        let crop = edit.cropState
        #expect(crop.preset == .threeByFour && !crop.isLandscape)
        let ratio = try #require(CropGeometry.ratio(for: .threeByFour, isLandscape: crop.isLandscape, imageSize: portraitSize))
        #expect(abs(pixelRatio(crop.rect, in: portraitSize) - ratio) < 1e-6)

        // Resizing in the turned photo keeps the ratio
        edit.resizeCrop(.bottomRight, from: crop.rect, byPoints: CGSize(width: -8, height: -8), in: portraitSize)
        #expect(abs(pixelRatio(edit.cropState.rect, in: portraitSize) - ratio) < 1e-6)
    }

    @Test func originalStaysOriginalAcrossATurn() {
        let edit = edit()
        edit.swapCropOrientation()
        edit.rotatePhoto()
        // Portrait crop of a landscape photo, turned: a landscape crop of a portrait photo
        let crop = edit.cropState
        #expect(crop.preset == .original && crop.isLandscape)
        #expect(abs(pixelRatio(crop.rect, in: portraitSize) - 4.0 / 3.0) < 1e-6)
        edit.resizeCrop(.bottomRight, from: crop.rect, byPoints: CGSize(width: -6, height: -6), in: portraitSize)
        #expect(abs(pixelRatio(edit.cropState.rect, in: portraitSize) - 4.0 / 3.0) < 1e-6)
    }

    @Test func theToolsResetClearsTheCropAndTheTurnButStockResetKeepsBoth() {
        let edit = edit()
        edit.select(tool: .crop)
        edit.selectCropPreset(.oneByOne)
        edit.rotatePhoto()
        edit.selectStock(.cine500T)
        edit.resetToStockDefaults()
        #expect(edit.look.quarterTurns == 1 && edit.look.crop != nil, "geometry survives the stock reset")

        edit.resetCrop()
        #expect(edit.look.quarterTurns == 0 && edit.look.crop == nil && !edit.canResetCrop)
        #expect(edit.look.stock == .cine500T, "the film look is untouched")
    }

    @Test func turnsAloneEnableTheToolsReset() {
        let edit = edit()
        #expect(!edit.canResetCrop)
        edit.rotatePhoto()
        #expect(edit.canResetCrop && edit.look.crop == nil)
        edit.resetCrop()
        #expect(edit.look.quarterTurns == 0)
    }

    @Test func downloadAndSaveCarryTheTurn() async throws {
        final class Box: @unchecked Sendable { var data: Data? }
        let box = Box()
        let edit = PhotoEditViewModel(preview: quadrants(landscapeSize), stock: .none, savePhotoData: { box.data = $0 })
        edit.rotatePhoto()
        await edit.download()
        let data = try #require(box.data)
        let image = try #require(UIImage(data: data))
        #expect(abs(image.size.width - 72) <= 1 && abs(image.size.height - 96) <= 1)
    }
}

// MARK: - No flash when leaving the Crop tool

@MainActor
struct CropLeaveStandInTests {

    private func edit() -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: quadrants(landscapeSize), stock: .portrait400)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    private func aspect(_ image: UIImage) -> CGFloat { image.size.width / image.size.height }

    @Test func leavingShowsTheCroppedFilmRenderAtOnceThenCrossFadesToTheNewRender() async {
        let edit = edit()
        await edit.renderSettled()
        edit.select(tool: .crop)
        await edit.renderSettled()
        edit.selectCropPreset(.oneByOne)

        edit.select(tool: .film)
        // The new render has not landed: still the right framing, never the whole frame
        #expect(edit.isRendering)
        #expect(abs(aspect(edit.displayedPhoto) - 1) < 0.001)
        #expect(edit.displayedPhoto !== edit.photo)
        let swaps = edit.standInSwaps

        await edit.renderSettled()
        #expect(abs(aspect(edit.displayedPhoto) - 1) < 0.001)
        #expect(edit.standInSwaps == swaps + 1, "one cross-fade from the stand-in to the render")
    }

    @Test func leavingBeforeTheOpeningRenderLandsFallsBackToThePlainCroppedPhoto() async {
        let edit = edit()
        edit.selectCropPreset(.oneByOne)
        await edit.renderSettled()
        // The render on screen carries the old square crop, so it cannot be cropped again
        edit.select(tool: .crop)
        edit.selectCropPreset(.fourByFive)
        edit.select(tool: .exposure)
        #expect(abs(aspect(edit.displayedPhoto) - 1.25) < 0.001)
        await edit.renderSettled()
        #expect(abs(aspect(edit.displayedPhoto) - 1.25) < 0.02)
    }

    @Test func aTurnNeverShowsTheUnturnedFrame() async {
        let edit = edit()
        await edit.renderSettled()
        edit.select(tool: .crop)
        await edit.renderSettled()
        edit.rotatePhoto()
        edit.select(tool: .film)
        #expect(abs(aspect(edit.displayedPhoto) - 72.0 / 96.0) < 0.001, "portrait at once")
        await edit.renderSettled()
        #expect(abs(aspect(edit.displayedPhoto) - 72.0 / 96.0) < 0.02)
    }

    @Test func resettingTheTurnInTheToolShowsTheUnturnedPhotoOnLeaving() async {
        let edit = edit()
        edit.rotatePhoto()
        await edit.renderSettled()
        edit.select(tool: .crop)
        await edit.renderSettled()
        edit.resetCrop()
        edit.select(tool: .film)
        #expect(abs(aspect(edit.displayedPhoto) - 96.0 / 72.0) < 0.001)
    }

    @Test func aFilmEditKeepsTheLastRenderUntilTheNewOneArrives() async {
        let edit = edit()
        await edit.renderSettled()
        let before = edit.displayedPhoto
        edit.selectStock(.cine500T)
        #expect(edit.displayedPhoto === before, "no stand-in for a look edit")
        await edit.renderSettled()
        #expect(edit.displayedPhoto !== before)
    }

    @Test func compareShowsThePlainTurnedAndCroppedPhoto() async {
        let edit = edit()
        edit.selectCropPreset(.oneByOne)
        edit.rotatePhoto()
        await edit.renderSettled()
        edit.setComparing(true)
        #expect(abs(aspect(edit.displayedPhoto) - 1) < 0.001)
    }
}
