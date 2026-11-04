import CoreImage
import SwiftData
import Testing
import UIKit
@testable import frmr

// F-122-F: the Crop tool. Geometry, the stored form, the render pipeline,
// strips (which ignore the crop) and the editor's view model.

private let portraitSize = CGSize(width: 3000, height: 4000)
private let landscapeSize = CGSize(width: 4000, height: 3000)

private func pixelRatio(_ rect: CGRect, in size: CGSize) -> CGFloat {
    (rect.width * size.width) / (rect.height * size.height)
}

private func isInside(_ rect: CGRect) -> Bool {
    rect.minX >= -1e-9 && rect.minY >= -1e-9 && rect.maxX <= 1 + 1e-9 && rect.maxY <= 1 + 1e-9
}

// MARK: - Geometry

struct CropGeometryTests {

    @Test(arguments: CropPreset.allCases, [portraitSize, landscapeSize])
    func everyPresetFitsCentredInsideTheImage(preset: CropPreset, size: CGSize) throws {
        let landscape = CropGeometry.defaultIsLandscape(for: size)
        let rect = CropGeometry.fit(preset, isLandscape: landscape, in: size)

        #expect(isInside(rect))
        #expect(abs(rect.midX - 0.5) < 1e-9 && abs(rect.midY - 0.5) < 1e-9, "centred")
        switch preset {
        case .original, .free:
            #expect(rect == CGRect(x: 0, y: 0, width: 1, height: 1))
        default:
            let ratio = try #require(CropGeometry.ratio(for: preset, isLandscape: landscape, imageSize: size))
            #expect(abs(pixelRatio(rect, in: size) - ratio) < 1e-6)
            #expect(rect.width > 0.999 || rect.height > 0.999, "the largest rect of that ratio")
            // The photo's own orientation: portrait photos get portrait frames
            #expect((ratio > 1) == landscape || ratio == 1)
        }
    }

    @Test func swapTurnsAFixedRatioKeepingAreaAndCentre() {
        let start = CropGeometry.fit(.threeByFour, isLandscape: false, in: portraitSize)
        let turned = CropGeometry.swapped(start, preset: .threeByFour, toLandscape: true, imageSize: portraitSize)

        #expect(abs(pixelRatio(turned, in: portraitSize) - 4.0 / 3.0) < 1e-6)
        #expect(isInside(turned))
        #expect(abs(turned.midX - 0.5) < 1e-9 && abs(turned.midY - 0.5) < 1e-9)
        // Too wide for the photo: shrunk to fit, never beyond it
        #expect(turned.width <= 1 + 1e-9)

        let small = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.2)
        let moved = CropGeometry.swapped(small, preset: .fourByFive, toLandscape: false, imageSize: landscapeSize)
        #expect(abs(pixelRatio(moved, in: landscapeSize) - 0.8) < 1e-6)
        let area = { (r: CGRect) in r.width * landscapeSize.width * r.height * landscapeSize.height }
        #expect(abs(area(moved) - area(small)) / area(small) < 1e-6, "same area when it fits")
    }

    @Test(arguments: CropGeometry.Handle.allCases)
    func resizingKeepsTheRatioAndStaysInside(handle: CropGeometry.Handle) throws {
        let size = landscapeSize
        let ratio: CGFloat = 4.0 / 5.0
        let seed = CropGeometry.swapped(
            CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.3), preset: .fourByFive, toLandscape: false, imageSize: size
        )
        let origin = CropGeometry.position(of: handle, on: seed)
        // Pull the handle inward, outward, and far past the photo
        for delta in [CGPoint(x: 0.05, y: 0.04), CGPoint(x: -0.05, y: -0.06), CGPoint(x: 3, y: 3), CGPoint(x: -3, y: -3)] {
            let next = CropGeometry.resized(
                seed, handle: handle, to: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y), imageSize: size, ratio: ratio
            )
            #expect(abs(pixelRatio(next, in: size) - ratio) < 1e-6, "\(handle) \(delta): ratio kept")
            #expect(isInside(next), "\(handle) \(delta): inside the photo")
            #expect(next.width * size.width >= CropGeometry.minimumSide(imageSize: size) - 1e-6)
            #expect(next.height * size.height >= CropGeometry.minimumSide(imageSize: size) - 1e-6)
        }
    }

    @Test func aFreeCornerMovesOnlyItsOwnSidesAndTheOppositeCornerStays() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let next = CropGeometry.resized(start, handle: .bottomRight, to: CGPoint(x: 0.9, y: 0.6), imageSize: landscapeSize, ratio: nil)
        #expect(next == CGRect(x: 0.2, y: 0.2, width: 0.7, height: 0.4))

        let edge = CropGeometry.resized(start, handle: .left, to: CGPoint(x: 0.1, y: 0.9), imageSize: landscapeSize, ratio: nil)
        #expect(edge.maxX == start.maxX && edge.minY == start.minY && edge.height == start.height)
        #expect(abs(edge.minX - 0.1) < 1e-9)
    }

    @Test func theFrameNeverFlipsOrShrinksBelowTheMinimum() {
        let size = landscapeSize
        let minimum = CropGeometry.minimumSide(imageSize: size)
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        // Dragged right across the opposite edge
        let next = CropGeometry.resized(start, handle: .topLeft, to: CGPoint(x: 0.95, y: 0.95), imageSize: size, ratio: nil)
        #expect(abs(next.width * size.width - minimum) < 1e-6 && abs(next.height * size.height - minimum) < 1e-6)
        #expect(next.maxX == start.maxX && next.maxY == start.maxY, "the opposite corner stays")
        #expect(minimum == CGFloat(Constants.Crop.minimumShortSideFraction) * 3000)
    }

    @Test func movingClampsInsideAndSnapsToEdges() {
        let start = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        #expect(CropGeometry.moved(start, by: CGSize(width: 2, height: -2)) == CGRect(x: 0.6, y: 0, width: 0.4, height: 0.4))
        let nearEdge = CropGeometry.moved(start, by: CGSize(width: 0.295, height: 0))
        #expect(abs(nearEdge.maxX - 1) < 1e-9, "within the snap distance of the right edge")
        #expect(CropGeometry.moved(start, by: CGSize(width: 0.1, height: 0.1)) == CGRect(x: 0.4, y: 0.4, width: 0.4, height: 0.4))
    }

    @Test func countsTheEdgesTheFrameLiesOn() {
        #expect(CropGeometry.edgesTouching(CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)) == 0)
        #expect(CropGeometry.edgesTouching(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)) == 2)
        #expect(CropGeometry.edgesTouching(CGRect(x: 0, y: 0, width: 1, height: 1)) == 4)
    }

    @Test func aPhotoIsFittedCentredInItsContainer() {
        let frame = CropGeometry.fittedFrame(imageSize: CGSize(width: 400, height: 200), in: CGSize(width: 100, height: 100))
        #expect(frame == CGRect(x: 0, y: 25, width: 100, height: 50))
    }
}

// MARK: - Stored form

struct CropStoredFormTests {

    @Test func aCropSurvivesACodableRoundTripWithItsPreset() throws {
        let crop = CropRect(rect: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6), preset: .fourByFive, isLandscape: true)
        let look = FilmLook.stockDefaults(for: .portrait400).with(crop: crop)
        let data = try #require(FilmLook.encoded(look))
        #expect(FilmLook.decoded(from: data) == look)
        #expect(FilmLook.decoded(from: data).crop?.preset == .fourByFive)
    }

    @Test func oldLooksHaveNoCrop() throws {
        let legacy = Data(#"{"stock":"none"}"#.utf8)
        #expect(FilmLook.decoded(from: legacy).crop == nil)
        let data = try #require(FilmLook.encoded(.stockDefaults(for: .cine500T)))
        #expect(!String(decoding: data, as: UTF8.self).contains("crop"), "no key is written without a crop")
        #expect(FilmLook.decoded(from: data).crop == nil)
    }

    @Test func anUnreadableCropReadsAsNone() {
        let bad = Data(#"{"stock":"none","crop":{"x":0.8,"y":0,"width":0.9,"height":1}}"#.utf8)
        #expect(FilmLook.decoded(from: bad).crop == nil)
        let missingFields = Data(#"{"stock":"none","crop":{"x":0.1}}"#.utf8)
        #expect(FilmLook.decoded(from: missingFields).crop == nil)
    }

    @Test func resetToStockDefaultsIgnoresTheCrop() {
        let crop = CropRect(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let look = FilmLook.stockDefaults(for: .slide100).with(crop: crop)
        #expect(look.isStockDefault, "a crop alone is not a look edit")
        #expect(look != FilmLook.stockDefaults(for: .slide100))
    }

    @Test func pixelRectsRoundToWholePixelsInsideTheImage() {
        let crop = CropRect(rect: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.6))
        #expect(crop.pixelRect(in: CGSize(width: 400, height: 300)) == CGRect(x: 100, y: 30, width: 200, height: 180))
        let sliver = CropRect(rect: CGRect(x: 0.999, y: 0.999, width: 0.0001, height: 0.0001))
        let pixels = sliver.pixelRect(in: CGSize(width: 10, height: 10))
        #expect(pixels.width >= 1 && pixels.height >= 1 && pixels.maxX <= 10 && pixels.maxY <= 10)
    }

    @Test func aWholePhotoCropIsNoCropForRendering() {
        #expect(FilmLook.original.with(crop: .fullFrame).hasActiveCrop == false)
        #expect(!FilmLook.original.with(crop: .fullFrame).altersOutput)
        #expect(FilmLook.original.with(crop: CropRect(rect: CGRect(x: 0, y: 0, width: 0.9, height: 1))).altersOutput)
    }
}

// MARK: - Render

struct CropRenderTests {

    private func patterned(_ size: CGSize, orientation: UIImage.Orientation = .up) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size.width / 2, height: size.height)))
            UIColor.blue.setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
            for index in 0..<10 {
                UIColor(white: CGFloat(index) / 10, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat(index) * size.width / 10, y: size.height * 0.4, width: size.width / 20, height: size.height * 0.2))
            }
        }
        guard let cgImage = image.cgImage else { return image }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private let crop = CropRect(rect: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.6))

    @Test func outputSizeIsTheCropTimesTheSourceForAnUprightPhoto() throws {
        let source = patterned(CGSize(width: 400, height: 300))
        for look in [FilmLook.original, .stockDefaults(for: .portrait400)] {
            let output = try ImageProcessor.renderFullLook(of: source, look: look.with(crop: crop), seed: 1)
            let cg = try #require(output.cgImage)
            #expect(abs(cg.width - 200) <= 1 && abs(cg.height - 180) <= 1, "\(look.stock)")
            #expect(output.imageOrientation == .up)
        }
    }

    @Test func cropsAreRelativeToTheUprightPhotoForExifRotatedSources() throws {
        // 128×64 sensor, red left / blue right, tagged .right: 64×128 upright, red on top
        let source = patterned(CGSize(width: 128, height: 64), orientation: .right)
        let top = CropRect(rect: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        let output = try ImageProcessor.renderFullLook(of: source, look: .original.with(crop: top), seed: 1)
        let cg = try #require(output.cgImage)
        #expect(output.imageOrientation == .right, "the capture's tag is kept")
        // Upright 64×64; stored in sensor space the same size
        #expect(cg.width == 64 && cg.height == 64)
        let pixels = try #require(PixelBuffer(cg))
        #expect(pixels.channelMeans.r > 200 && pixels.channelMeans.b < 60, "the top half of the upright photo is the red half")

        let bottom = CropRect(rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        let lower = try ImageProcessor.renderFullLook(of: source, look: .original.with(crop: bottom), seed: 1)
        let lowerPixels = try #require(PixelBuffer(lower))
        #expect(lowerPixels.channelMeans.b > 200 && lowerPixels.channelMeans.r < 60)

        // A narrow upright crop: width × height swap in sensor space
        let narrow = CropRect(rect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
        let sized = try ImageProcessor.renderFullLook(of: source, look: .original.with(crop: narrow), seed: 1)
        let sizedCG = try #require(sized.cgImage)
        #expect(abs(sizedCG.width - 128) <= 1 && abs(sizedCG.height - 32) <= 1)
    }

    @Test func aCropThenFilmEqualsFilmOnTheCroppedPhoto() throws {
        // Grain, vignette and light leak lay out on the cropped frame
        let source = patterned(CGSize(width: 400, height: 300))
        var look = FilmLook.stockDefaults(for: .cine500T)
        look.strengths.vignette = 1
        look.strengths.lightLeak = 1
        look.strengths.grain = 1
        let viaCrop = try ImageProcessor.renderFullLook(of: source, look: look.with(crop: crop), seed: 9)

        let cropped = try #require(source.cgImage?.cropping(to: CGRect(x: 100, y: 30, width: 200, height: 180)))
        let direct = try ImageProcessor.renderFullLook(of: UIImage(cgImage: cropped), look: look, seed: 9)

        let a = try #require(PixelBuffer(viaCrop)), b = try #require(PixelBuffer(direct))
        #expect(a.width == b.width && a.height == b.height)
        // Same maths either way; only float rounding in the lattice may differ by a level
        let worst = zip(a.bytes, b.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 2)
    }

    @Test func noCropOrAWholePhotoCropRendersAsBefore() throws {
        let source = patterned(CGSize(width: 200, height: 150))
        let look = FilmLook.stockDefaults(for: .portrait400)
        let plain = try ImageProcessor.renderFullLook(of: source, look: look, seed: 3)
        let whole = try ImageProcessor.renderFullLook(of: source, look: look.with(crop: .fullFrame), seed: 3)
        #expect(PixelBuffer(plain) == PixelBuffer(whole))

        let untouched = try ImageProcessor.renderFullLook(of: source, look: .original.with(crop: .fullFrame), seed: 3)
        #expect(untouched === source, "Off with no crop is the original itself")
    }

    @Test func aCropAloneRendersWithoutAFilmLook() throws {
        let source = patterned(CGSize(width: 200, height: 100))
        let output = try ImageProcessor.renderFullLook(
            of: source, look: .original.with(crop: CropRect(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))), seed: 1
        )
        #expect(output !== source)
        #expect(output.cgImage?.width == 100 && output.cgImage?.height == 50)
    }

    @Test func aCoveringSizeShrinksTheCroppedFrame() throws {
        let source = patterned(CGSize(width: 800, height: 600))
        let output = try ImageProcessor.renderFullLook(
            of: source, look: .stockDefaults(for: .slide100).with(crop: crop), seed: 1,
            coveringPixelSize: CGSize(width: 100, height: 100)
        )
        let cg = try #require(output.cgImage)
        // 400×360 cropped, shrunk to cover 100×100
        #expect(cg.width >= 100 && cg.height >= 100 && cg.width < 400)
        #expect(abs(Double(cg.width) / Double(cg.height) - 400.0 / 360.0) < 0.03)
    }

    @Test func theDisplayCacheDecodesBigEnoughForACrop() throws {
        let cache = FilmLookCache(costLimitBytes: 10_000_000)
        let source = patterned(CGSize(width: 800, height: 600))
        let small = CropRect(rect: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        let covering = small.sourceCoveringSize(forOutput: CGSize(width: 50, height: 50))
        #expect(covering == CGSize(width: 200, height: 200))

        let id = UUID()
        let image = cache.image(id: id, look: .original.with(crop: small), seed: 1, pixelSize: CGSize(width: 50, height: 50)) { source }
        // The 200×150 crop, shrunk to cover 50×50
        #expect(image?.cgImage.map { abs($0.width - 67) <= 1 && $0.height == 50 } == true)
        let other = cache.image(id: id, look: .original, seed: 1, pixelSize: CGSize(width: 50, height: 50)) { source }
        #expect(other === source, "a different look is a different cache entry")
    }
}

// MARK: - Strips

struct CropStripTests {

    @Test func aStripShowsTheWholePhotoWhateverItsCrop() {
        let photo = solidImage(.orange, size: CGSize(width: 120, height: 90))
        let look = FilmLook.stockDefaults(for: .portrait400)
        let cropped = look.with(crop: CropRect(rect: CGRect(x: 0, y: 0, width: 0.4, height: 0.4)))
        func strip(_ look: FilmLook) -> UIImage {
            let cells = (0..<Constants.entriesPerStrip).map { _ in StripGenerator.Cell(image: photo, caption: "", look: look) }
            return StripGenerator.render(strip: cells, customization: StripCustomization(), date: Date(timeIntervalSince1970: 1_000))
        }
        #expect(PixelBuffer(strip(look)) == PixelBuffer(strip(cropped)))
        #expect(cropped.customization == look.customization, "the strip description has no crop")
    }
}

// MARK: - Editor

@MainActor
struct CropEditorTests {

    private func photo(_ size: CGSize = CGSize(width: 96, height: 72)) -> UIImage {
        solidImage(.gray, size: size)
    }

    private func edit(_ size: CGSize = CGSize(width: 96, height: 72)) -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: photo(size), stock: .portrait400)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
    }

    @Test func cropComesAfterHighlightsInTheToolRow() {
        let ids = PhotoEditViewModel.Tool.allTools.map(\.id)
        #expect(Array(ids.prefix(8)) == ["exposure", "shadows", "highlights", "contrast", "saturation", "crop", "film", "print"])
        #expect(PhotoEditViewModel.Tool(id: "crop") == .crop)
        let items = PhotoEditView.toolItems(look: .stockDefaults(for: .portrait400), exposureReadout: "0 EV", cropReadout: "3:4")
        #expect(items[5].id == "crop" && items[5].systemImage == "crop" && items[5].value == "3:4" && items[5].ring == nil)
    }

    @Test func choosingAPresetFitsItInThePhotosOrientation() {
        let edit = edit()
        edit.select(tool: .crop)
        #expect(edit.cropState.rect == CropRect.fullFrame.rect && edit.cropState.preset == .original && !edit.canResetCrop)

        edit.selectCropPreset(.oneByOne)
        let square = edit.cropState
        #expect(square.preset == .oneByOne && edit.look.crop == square)
        #expect(abs(pixelRatio(square.rect, in: CGSize(width: 96, height: 72)) - 1) < 1e-6)

        edit.selectCropPreset(.sixteenByNine)
        #expect(edit.cropState.isLandscape, "a landscape photo starts landscape")
        #expect(abs(pixelRatio(edit.cropState.rect, in: CGSize(width: 96, height: 72)) - 16.0 / 9.0) < 1e-6)

        let sixteenByNine = edit.cropState.rect
        edit.selectCropPreset(.free)
        #expect(edit.cropState.preset == .free && edit.cropState.rect == sixteenByNine, "Free keeps the frame")

        edit.selectCropPreset(.original)
        #expect(edit.look.crop == nil, "Original on the whole photo is no crop")
    }

    @Test func swappingTurnsAFixedRatio() {
        let edit = edit()
        edit.selectCropPreset(.threeByFour)
        #expect(edit.canSwapCropOrientation)
        let size = CGSize(width: 96, height: 72)
        #expect(abs(pixelRatio(edit.cropState.rect, in: size) - 4.0 / 3.0) < 1e-6)
        edit.swapCropOrientation()
        #expect(!edit.cropState.isLandscape && abs(pixelRatio(edit.cropState.rect, in: size) - 0.75) < 1e-6)

        edit.selectCropPreset(.oneByOne)
        let before = edit.cropState
        edit.swapCropOrientation()
        #expect(edit.cropState == before && !edit.canSwapCropOrientation)
    }

    @Test func draggingMovesAndResizesAndReportsNewEdges() {
        let edit = edit()
        edit.select(tool: .crop)
        edit.selectCropPreset(.oneByOne)
        let start = edit.cropState.rect
        let frame = CGSize(width: 96, height: 72)

        #expect(!edit.moveCrop(from: start, byPoints: CGSize(width: 2, height: 0), in: frame))
        #expect(edit.cropState.rect.minX > start.minX)
        #expect(edit.moveCrop(from: start, byPoints: CGSize(width: 500, height: 0), in: frame), "reached the right edge")
        #expect(abs(edit.cropState.rect.maxX - 1) < 1e-9)

        let before = edit.cropState.rect
        edit.resizeCrop(.topLeft, from: before, byPoints: CGSize(width: 10, height: 10), in: frame)
        #expect(abs(pixelRatio(edit.cropState.rect, in: frame) - 1) < 1e-6, "the preset's ratio holds")
        #expect(edit.cropState.rect.width < before.width)
    }

    @Test func resetBringsBackTheWholePhotoButKeepsTheTool() {
        let edit = edit()
        edit.select(tool: .crop)
        edit.selectCropPreset(.fourByFive)
        #expect(edit.canResetCrop && edit.isModified)
        edit.resetCrop()
        #expect(edit.look.crop == nil && edit.cropState.rect == CropRect.fullFrame.rect && !edit.canResetCrop && edit.tool == .crop)
    }

    @Test func theCropSurvivesAStockChangeAndResetToStockDefaults() {
        let edit = edit()
        edit.selectCropPreset(.oneByOne)
        let crop = edit.look.crop
        edit.selectStock(.cine500T)
        edit.selectPrint(nil)
        edit.setExposure(1)
        #expect(edit.look.crop == crop)
        #expect(edit.canResetToStockDefaults)
        edit.resetToStockDefaults()
        #expect(edit.look.crop == crop, "crop is geometry, not look")
        #expect(!edit.canResetToStockDefaults, "a crop alone does not enable Reset to stock defaults")
    }

    @Test func theWholePhotoShowsWhileCroppingAndTheCroppedResultAfter() async {
        let original = photo(CGSize(width: 96, height: 72))
        let edit = PhotoEditViewModel(preview: original, stock: .portrait400)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        await edit.renderSettled()

        edit.select(tool: .crop)
        edit.selectCropPreset(.oneByOne)
        #expect(edit.displayedPhoto === original, "the plain, whole photo under the frame")
        await edit.renderSettled()

        edit.select(tool: .film)
        await edit.renderSettled()
        let shown = edit.displayedPhoto
        #expect(shown !== original)
        let cg = shown.cgImage
        #expect(cg != nil && cg?.width == cg?.height, "the square crop")

        edit.setComparing(true)
        #expect(edit.displayedPhoto !== shown, "Compare shows the plain photo, still cropped")
        #expect(edit.displayedPhoto.size.width == edit.displayedPhoto.size.height)
    }

    @Test func aCropOnAnOffLookStillRendersAndOpeningTheToolDoesNotRenderTheCrop() async {
        let edit = PhotoEditViewModel(preview: photo(), stock: .none)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        edit.selectCropPreset(.oneByOne)
        await edit.renderSettled()
        let cg = edit.renderedPhoto?.cgImage
        #expect(cg != nil && cg?.width == cg?.height)
    }

    @Test func aReEditOpensOnItsStoredCropAndSaveAndDiscardTreatItRight() async throws {
        let context = try context()
        let stored = FilmLook.stockDefaults(for: .portrait400)
            .with(crop: CropRect(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), preset: .free))
        let row = try RollViewModel.insert(original: photo(), look: stored, capturedAt: .now, context: context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: row.photoPath)) }

        let discarded = try #require(PhotoEditViewModel(editing: row))
        #expect(discarded.look.crop == stored.crop && discarded.cropState.preset == .free && !discarded.isModified)
        discarded.resetCrop()
        discarded.discard()
        #expect(row.look.crop == stored.crop, "Discard keeps the stored crop")

        let saved = try #require(PhotoEditViewModel(editing: row))
        saved.selectCropPreset(.oneByOne)
        saved.selectStock(.cine500T)
        #expect(await saved.saveToRoll(context: context))
        #expect(row.look.crop == saved.look.crop && row.look.crop?.preset == .oneByOne && row.look.stock == .cine500T)

        let cleared = try #require(PhotoEditViewModel(editing: row))
        cleared.resetCrop()
        #expect(await cleared.saveToRoll(context: context))
        #expect(row.look.crop == nil)
    }

    @Test func downloadWritesTheCroppedFile() async throws {
        final class Box: @unchecked Sendable { var data: Data? }
        let box = Box()
        let edit = PhotoEditViewModel(preview: photo(CGSize(width: 96, height: 72)), stock: .none, savePhotoData: { box.data = $0 })
        edit.selectCropPreset(.oneByOne)
        await edit.download()
        let data = try #require(box.data)
        let image = try #require(UIImage(data: data))
        #expect(abs(image.size.width - 72) <= 1 && abs(image.size.height - 72) <= 1)
    }
}
