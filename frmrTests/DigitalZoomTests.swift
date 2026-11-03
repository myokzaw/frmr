import CoreGraphics
import SwiftData
import UIKit
import Testing
@testable import frmr

// F-122-G: digital zoom is an app-side value (1...3 in 0.2 steps). The
// viewfinder is scaled about its centre and the saved look carries a
// centred crop, so the device stays at 1x and RAW is always allowed.

struct DigitalZoomMathTests {

    @Test(arguments: [(0.2, 1.0), (1.0, 1.0), (1.09, 1.0), (1.1, 1.2), (1.3, 1.4), (2.5, 2.6), (2.9, 3.0), (3.0, 3.0), (9.0, 3.0)] as [(CGFloat, CGFloat)])
    func zoomClampsAndSnapsToFifthsOfAWhole(input: CGFloat, expected: CGFloat) {
        #expect(abs(DigitalZoom.clamped(input) - expected) < 1e-9)
    }

    @Test func nonFiniteZoomReadsAsOneTimes() {
        #expect(DigitalZoom.clamped(.nan) == 1)
        #expect(DigitalZoom.clamped(.infinity) == 1)
    }

    @Test func theReadoutHasOneDecimalAndOneTimesIsPlain() {
        #expect(DigitalZoom.readout(1) == "1×")
        #expect(DigitalZoom.readout(1.4) == "1.4×")
        #expect(DigitalZoom.readout(2.4) == "2.4×")
        #expect(DigitalZoom.readout(3) == "3.0×")
        #expect(DigitalZoom.spokenValue(2.4) == "2.4" && DigitalZoom.spokenValue(1) == "1")
    }

    @Test func theRulerTicksEveryFifthWithFirmTicksAtWholeTimes() {
        let scale = ScrubberScale.cameraZoom
        #expect(scale.step == 0.2 && Constants.Camera.zoomStep == 0.2)
        #expect(scale.range == 1...3)
        #expect(ScrubberMath.stepCount(in: scale.range, step: scale.step) == 10)
        #expect(scale.tickSpacing >= 22, "a step is at least as far as it was")
        let firm = (0...10).filter { ScrubberMath.tickKind(at: $0, in: scale.range, step: scale.step, hapticStep: scale.majorStep, reference: scale.reference, firmStep: scale.firmStep) == .reference }
        #expect(firm == [0, 5, 10], "1x, 2x and 3x")
    }

    @Test func smoothingConvergesAndNeverOvershoots() {
        for (start, target) in [(1.0, 2.0), (3.0, 1.0), (1.0, 1.2)] as [(CGFloat, CGFloat)] {
            var current = start
            var steps = 0
            while current != target, steps < 200 {
                let next = DigitalZoom.next(current: current, target: target, dt: 1.0 / 30)
                #expect(abs(next - target) <= abs(current - target), "moves toward the target")
                #expect((next - target) * (start - target) >= 0, "never crosses it")
                current = next
                steps += 1
            }
            #expect(current == target, "lands exactly")
            #expect(steps < 30, "about a third of a second at 30 fps")
        }
    }

    @Test func smoothingIsAtRestAtTheTargetAndIgnoresBadTimeSteps() {
        #expect(DigitalZoom.next(current: 2, target: 2, dt: 0.033) == 2)
        #expect(DigitalZoom.next(current: 1, target: 2, dt: 0) == 1)
        #expect(DigitalZoom.next(current: 1, target: 2, dt: -1) == 1)
        let stalled = DigitalZoom.next(current: 1, target: 3, dt: 50)
        #expect(stalled > 1 && stalled < 3, "a stalled frame can't leap to the target")
    }

    @Test func noCropAtOneTimes() {
        #expect(DigitalZoom.cropRect(zoom: 1, isLandscape: false) == nil)
    }

    @Test(arguments: [false, true])
    func twoTimesIsTheCentredHalf(isLandscape: Bool) throws {
        let crop = try #require(DigitalZoom.cropRect(zoom: 2, isLandscape: isLandscape))
        #expect(crop.rect == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(crop.preset == .original)
        #expect(crop.isLandscape == isLandscape)
        #expect(crop.isValid && !crop.isFullFrame)
    }

    @Test(arguments: [1.4, 1.37, 2.4, 3.0] as [CGFloat])
    func theCropIsCentredAtOneOverZoom(zoom: CGFloat) throws {
        let crop = try #require(DigitalZoom.cropRect(zoom: zoom, isLandscape: false))
        let side = 1 / Double(zoom)
        #expect(abs(crop.width - side) < 1e-9 && abs(crop.height - side) < 1e-9)
        #expect(abs((crop.x + crop.width / 2) - 0.5) < 1e-9 && abs((crop.y + crop.height / 2) - 0.5) < 1e-9)
    }

    @Test func theCaptureCropFollowsThePhotoOrientation() throws {
        let portrait = try #require(CameraViewModel.captureCrop(zoom: 2, photoSize: CGSize(width: 3000, height: 4000)))
        let landscape = try #require(CameraViewModel.captureCrop(zoom: 2, photoSize: CGSize(width: 4000, height: 3000)))
        #expect(!portrait.isLandscape && landscape.isLandscape)
        #expect(CameraViewModel.captureCrop(zoom: 1, photoSize: CGSize(width: 3000, height: 4000)) == nil)
    }

    @Test func aTapAtTheVisibleCentreIsTheDeviceCentre() {
        let size = CGSize(width: 300, height: 400)
        for zoom in [1, 2, 3] as [CGFloat] {
            let mapped = DigitalZoom.unscaledPoint(CGPoint(x: 150, y: 200), zoom: zoom, in: size)
            #expect(mapped == CGPoint(x: 150, y: 200))
        }
    }

    @Test func aVisibleCornerIsTheCornerOfTheZoomedRect() {
        let size = CGSize(width: 300, height: 400)
        // At 2x the visible frame is the centred half: (75, 100)...(225, 300)
        #expect(DigitalZoom.unscaledPoint(.zero, zoom: 2, in: size) == CGPoint(x: 75, y: 100))
        #expect(DigitalZoom.unscaledPoint(CGPoint(x: 300, y: 400), zoom: 2, in: size) == CGPoint(x: 225, y: 300))
        // At 1x nothing moves
        #expect(DigitalZoom.unscaledPoint(CGPoint(x: 300, y: 400), zoom: 1, in: size) == CGPoint(x: 300, y: 400))
    }

    @Test func scalingAndUnscalingRoundTrip() {
        let size = CGSize(width: 300, height: 400)
        let point = CGPoint(x: 40, y: 330)
        for zoom in [1, 1.7, 3] as [CGFloat] {
            let back = DigitalZoom.scaledPoint(DigitalZoom.unscaledPoint(point, zoom: zoom, in: size), zoom: zoom, in: size)
            #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
        }
    }

    @Test func theFilmPreviewScalesAboutTheCentre() {
        let frame = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let drawable = CGSize(width: 300, height: 400)
        let plain = FilmPreviewRenderer.previewImage(frame, cube: nil, drawableSize: drawable)
        let zoomed = FilmPreviewRenderer.previewImage(frame, cube: nil, drawableSize: drawable, zoom: 2)
        #expect(plain.extent == CGRect(origin: .zero, size: drawable))
        #expect(zoomed.extent == CGRect(origin: .zero, size: drawable), "still cropped to the drawable")
        #expect(FilmPreviewRenderer.previewImage(frame, cube: nil, drawableSize: drawable, zoom: 0.5).extent == plain.extent, "below 1 reads as 1")
    }

    @Test func deviceRawIsAllowedBecauseTheDeviceStaysAtOneTimes() {
        // F-122-G: zoom never reaches the device, so the RAW rule always holds
        #expect(CaptureSession.canCaptureBayerRaw(zoomFactor: 1, isRampingZoom: false, cropFactor: 1))
    }
}

@MainActor
struct DigitalZoomViewModelTests {

    private func makeCamera() throws -> CameraViewModel {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        camera.switchOperation = { _, _ in true }
        camera.awaitNewFrame = {}
        return camera
    }

    private func photo(_ size: CGSize = CGSize(width: 120, height: 160)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func pinchAndRulerShareOneValue() throws {
        let camera = try makeCamera()
        camera.pinchBegan()
        camera.pinchChanged(scale: 2.04)
        #expect(abs(camera.zoomFactor - 2.0) < 1e-9)
        camera.pinchEnded()
        camera.setZoom(2.4)
        #expect(abs(camera.zoomFactor - 2.4) < 1e-9)
        // A pinch after the ruler continues from the ruler's value
        camera.pinchChanged(scale: 1.1)
        #expect(abs(camera.zoomFactor - 2.6) < 1e-9)
        camera.pinchEnded()
        #expect(camera.zoomReadout == "2.6×")
        #expect(camera.filmPreviewRenderer.targetZoom == camera.zoomFactor, "the film preview follows")
    }

    @Test func theViewfinderFollowsTheLiveValueAndTheReadoutSnaps() throws {
        let camera = try makeCamera()
        camera.pinchBegan()
        camera.pinchChanged(scale: 1.47)
        #expect(abs(camera.previewZoom - 1.47) < 1e-9, "the picture is continuous")
        #expect(abs(camera.zoomFactor - 1.4) < 1e-9, "the stored value snaps")
        #expect(camera.zoomReadout == "1.4×" && camera.isZoomLive)
        #expect(camera.filmPreviewRenderer.zoom == camera.previewZoom, "no smoothing under the fingers")
        camera.pinchChanged(scale: 9)
        #expect(camera.previewZoom == Constants.Camera.maxDigitalZoom)
        camera.pinchChanged(scale: 1.47)
        camera.pinchEnded()
        #expect(!camera.isZoomLive)
        #expect(abs(camera.previewZoom - 1.4) < 1e-9, "after the gesture the picture settles on the snapped value")
        #expect(abs(camera.filmPreviewRenderer.targetZoom - 1.4) < 1e-9)
    }

    @Test func aRulerDragFollowsTheRawPositionToo() throws {
        let camera = try makeCamera()
        camera.scrubZoom(1.73)
        #expect(abs(camera.previewZoom - 1.73) < 1e-9)
        camera.setZoom(1.73)
        #expect(abs(camera.zoomFactor - 1.8) < 1e-9 && abs(camera.previewZoom - 1.73) < 1e-9)
        camera.scrubZoom(nil)
        #expect(abs(camera.previewZoom - 1.8) < 1e-9)
    }

    @Test func aShotTakenMidGestureIsCroppedToTheLiveZoom() throws {
        let camera = try makeCamera()
        camera.pinchBegan()
        camera.pinchChanged(scale: 1.47)
        #expect(abs(camera.captureZoom - 1.47) < 1e-9)
        let live = try #require(CameraViewModel.captureCrop(zoom: camera.captureZoom, photoSize: CGSize(width: 120, height: 160)))
        #expect(abs(live.width - 1 / 1.47) < 1e-9)
        camera.pinchEnded()
        #expect(abs(camera.captureZoom - 1.4) < 1e-9, "otherwise the snapped value")
    }

    @Test func theGlideIsShortAndOffMidGestureOrWithReduceMotion() throws {
        let camera = try makeCamera()
        #expect(camera.zoomGlideAnimation(reduceMotion: false) != nil)
        #expect(camera.zoomGlideAnimation(reduceMotion: true) == nil)
        camera.scrubZoom(1.5)
        #expect(camera.zoomGlideAnimation(reduceMotion: false) == nil)
    }

    @Test func zoomStaysInOneToThree() throws {
        let camera = try makeCamera()
        camera.setZoom(9)
        #expect(camera.zoomFactor == Constants.Camera.maxDigitalZoom)
        camera.setZoom(camera.zoomFactor + Constants.Camera.zoomStep)
        #expect(camera.zoomFactor == Constants.Camera.maxDigitalZoom)
        camera.setZoom(0)
        #expect(camera.zoomFactor == 1)
        camera.setZoom(camera.zoomFactor - Constants.Camera.zoomStep)
        #expect(camera.zoomFactor == 1)
    }

    @Test func doubleTapResetsToOneTimes() throws {
        let camera = try makeCamera()
        camera.setZoom(2.2)
        camera.resetZoom()
        #expect(camera.zoomFactor == 1)
    }

    @Test func switchingLensResetsZoom() async throws {
        let camera = try makeCamera()
        camera.setZoom(2.2)
        camera.selectLens(.telephoto)
        #expect(camera.zoomFactor == 1)
        await camera.switchSettled()
        #expect(camera.zoomFactor == 1)
    }

    @Test func flippingResetsZoomAndTheFrontCameraHasNone() async throws {
        let camera = try makeCamera()
        camera.setZoom(2.2)
        camera.togglePanel(.zoom)
        camera.flipCamera()
        #expect(camera.zoomFactor == 1)
        #expect(camera.cameraPosition == .front && !camera.isZoomEnabled)
        #expect(camera.openPanel == nil, "the Zoom control closes for the front camera")
        await camera.switchSettled()

        camera.pinchBegan()
        camera.pinchChanged(scale: 2)
        camera.setZoom(2)
        camera.setZoom(2.6)
        camera.toggleZoomPanel()
        #expect(camera.zoomFactor == 1 && camera.openPanel == nil)
    }

    @Test func aFailedSwitchKeepsTheZoom() async throws {
        let camera = try makeCamera()
        camera.switchOperation = { _, _ in false }
        camera.setZoom(1.8)
        camera.selectLens(.telephoto)
        await camera.switchSettled()
        #expect(camera.selectedLens == .wide)
        #expect(abs(camera.zoomFactor - 1.8) < 1e-9)
    }

    @Test func tappingTheSelectedLensOpensTheZoomSheetAndAnotherSwitches() async throws {
        let camera = try makeCamera()
        camera.lensTapped(.wide)
        #expect(camera.openPanel == .zoom && camera.isZoomPanelExpanded)
        camera.lensTapped(.wide)
        #expect(camera.openPanel == nil, "tapping again closes it")

        camera.togglePanel(.exposure)
        camera.lensTapped(.wide)
        #expect(camera.openPanel == .zoom && !camera.isExposurePanelExpanded, "one control at a time")

        camera.lensTapped(.telephoto)
        #expect(camera.selectedLens == .telephoto)
        await camera.switchSettled()
    }

    @Test func theSelectedChipShowsTheZoomWhileZoomed() throws {
        let camera = try makeCamera()
        #expect(camera.lensChipText(for: .wide) == "1×")
        camera.setZoom(2.4)
        #expect(camera.lensChipText(for: .wide) == "2.4×")
        #expect(camera.lensChipText(for: .telephoto) == "Tele", "other chips keep their own value")
        camera.resetZoom()
        #expect(camera.lensChipText(for: .wide) == "1×")
    }

    @Test func aZoomedShotStoresACropAndAFullOneDoesNot() async throws {
        let camera = try makeCamera()
        let crop = CameraViewModel.captureCrop(zoom: 2, photoSize: CGSize(width: 120, height: 160))
        let zoomed = camera.beginPhotoEdit(preview: photo(), stock: .portrait400, crop: crop, savePhotoData: { _ in })
        #expect(zoomed.look.crop?.rect == CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(zoomed.look.crop?.preset == .original && zoomed.look.crop?.isLandscape == false)
        #expect(zoomed.look.quarterTurns == 0)
        #expect(!zoomed.isModified, "the zoom crop is the starting look, not an edit")

        let plain = camera.beginPhotoEdit(preview: photo(), stock: .portrait400, savePhotoData: { _ in })
        #expect(plain.look.crop == nil)
    }

    @Test func savingStraightToTheRollKeepsTheZoomCrop() async throws {
        let camera = try makeCamera()
        let context = ModelContext(try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
        let crop = CameraViewModel.captureCrop(zoom: 3, photoSize: CGSize(width: 160, height: 120))
        let saved = await camera.saveStraightToRoll(preview: photo(CGSize(width: 160, height: 120)), stock: .portrait400, crop: crop, context: context)
        let row = try #require(saved)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: row.photoPath)) }
        #expect(row.look.crop?.isLandscape == true)
        #expect(abs((row.look.crop?.width ?? 0) - 1.0 / 3.0) < 1e-9)

        let plain = await camera.saveStraightToRoll(preview: photo(), stock: .portrait400, context: context)
        let plainRow = try #require(plain)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: plainRow.photoPath)) }
        #expect(plainRow.look.crop == nil)
    }
}

// F-122-G: in Film strip mode a zoomed shot fills its slot with the zoomed
// framing, because strips ignore a look's crop.
@MainActor
struct PhotoboothZoomTests {
    private func photo(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func aZoomedSlotIsCutToTheZoomedFraming() throws {
        let slot = CameraViewModel.photoboothSlotImage(photo(width: 300, height: 400), zoom: 2)
        let cgImage = try #require(slot.cgImage)
        #expect(abs(cgImage.width - 150) <= 1)
        #expect(abs(cgImage.height - 200) <= 1)
    }

    @Test func aSlotAtOneTimesIsTheWholePhoto() {
        let image = photo(width: 300, height: 400)
        #expect(CameraViewModel.photoboothSlotImage(image, zoom: 1) === image)
    }
}
