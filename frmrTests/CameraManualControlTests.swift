import AVFoundation
import Foundation
import Testing
@testable import frmr

// v5 F1 (launch in Photo) and F3 (white balance Kelvin/tint, third-stop EV,
// one panel at a time). The simulator has no camera: device-facing calls
// are no-ops, so these test the state and the pure mappings.

@MainActor
struct PhotoModeLaunchTests {

    @Test func theAppLaunchesInPhotoMode() throws {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        #expect(camera.mode == .photo && camera.isPhotoMode)
        #expect(!camera.isPhotoboothMode)
        #expect(CameraViewModel.launchMode == .photo)
    }

    @Test func theStoredCaptureModeNoLongerDecidesTheLaunchMode() throws {
        // OPEN: v5-9 — an old install that stored Diary or Film strip still opens on Photo
        for stored in ["diary", "photobooth", "photo", "garbage"] {
            let defaults = try makeScratchDefaults()
            defaults.set(stored, forKey: Constants.DefaultsKeys.captureMode)
            #expect(CameraViewModel(defaults: defaults).mode == .photo, "stored \(stored)")
        }
        #expect(!Constants.Camera.launchModeFollowsStoredCaptureMode)
    }

    @Test func theSwitchIsPhotoAndFilmStripOnly() {
        #expect(CameraViewModel.Mode.allCases == [.photo, .photobooth])
        #expect(CameraViewModel.Mode.allCases.map(\.label) == ["Photo", "Film strip"])
    }

    @Test func filmStripIsSelectableForTheSessionOnly() throws {
        let defaults = try makeScratchDefaults()
        let camera = CameraViewModel(defaults: defaults)
        camera.selectPhotoboothMode()
        #expect(camera.isPhotoboothMode && !camera.isPhotoMode)
        camera.selectPhotoMode()
        #expect(camera.isPhotoMode)

        camera.selectPhotoboothMode()
        #expect(CameraViewModel(defaults: defaults).mode == .photo, "the choice is not remembered")
    }

    // v5.1 F9: the dial, white balance, exposure and the one-open-panel rule
    // are camera state, not Photo-mode state: Film strip uses them as is.
    @Test func dialWhiteBalanceExposureAndPanelsWorkTheSameInFilmStripMode() throws {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        camera.selectPhotoboothMode()

        camera.selectFilmStock(.portrait400)
        #expect(camera.filmStock == .portrait400 && camera.showsFilmPreview)

        camera.setWhiteBalance(kelvin: 4200, tint: 10)
        #expect(camera.whiteBalanceKelvin == 4200 && camera.whiteBalanceTint == 10 && camera.isWhiteBalanceCustom)

        camera.setExposureBias(0.4)
        #expect(camera.exposureBias == CameraViewModel.snappedExposureBias(0.4))

        camera.togglePanel(.whiteBalance)
        camera.togglePanel(.exposure)
        #expect(camera.openPanel == .exposure, "one panel open at a time")
        #expect(camera.mode == .photobooth, "none of it changed the mode")
    }
}

@MainActor
struct CameraPanelTests {

    private func camera() throws -> CameraViewModel {
        let defaults = try makeScratchDefaults()
        return CameraViewModel(defaults: defaults)
    }

    @Test func onlyOneOfFilmWhiteBalanceAndExposureIsOpen() throws {
        let camera = try camera()
        #expect(camera.openPanel == nil)
        for panel in [CameraViewModel.Panel.film, .whiteBalance, .exposure] {
            camera.togglePanel(panel)
            #expect(camera.openPanel == panel)
            #expect(camera.isFilmStockExpanded == (panel == .film))
            #expect(camera.isWhiteBalanceExpanded == (panel == .whiteBalance))
            #expect(camera.isExposurePanelExpanded == (panel == .exposure))
        }
        camera.togglePanel(.exposure)
        #expect(camera.openPanel == nil, "toggling the open panel closes it")
    }

    @Test func theNamedTogglesShareTheSameSlot() throws {
        let camera = try camera()
        camera.toggleExposurePanel()
        camera.toggleWhiteBalanceExpansion()
        #expect(camera.isWhiteBalanceExpanded && !camera.isExposurePanelExpanded)
        camera.toggleFilmStockExpansion()
        #expect(camera.isFilmStockExpanded && !camera.isWhiteBalanceExpanded)
        camera.toggleExposurePanel()
        #expect(camera.isExposurePanelExpanded && !camera.isFilmStockExpanded)
    }

    @Test func tappingTheViewfinderClosesWhicheverPanelIsOpen() throws {
        let camera = try camera()
        camera.toggleExposurePanel()
        camera.userTapped(at: .zero)
        #expect(camera.openPanel == nil)
        camera.closePanels()
        #expect(camera.openPanel == nil)
    }

    @Test func aListSelectionClosesItsOwnPanelOnly() throws {
        let camera = try camera()
        camera.toggleWhiteBalanceExpansion()
        camera.selectWhiteBalance(.tungsten)
        #expect(camera.openPanel == nil)

        camera.toggleWhiteBalanceExpansion()
        camera.chooseWhiteBalancePreset(.shade)
        #expect(camera.isWhiteBalanceExpanded, "the Photo panel keeps its sliders open")

        camera.toggleExposurePanel()
        camera.selectFilmStock(.slide100)
        #expect(camera.isExposurePanelExpanded, "a stock pick doesn't close another panel")
    }
}

@MainActor
struct WhiteBalanceControlTests {

    private func camera() throws -> CameraViewModel {
        let defaults = try makeScratchDefaults()
        return CameraViewModel(defaults: defaults)
    }

    @Test func startsOnAutoReadingAuto() throws {
        let camera = try camera()
        #expect(camera.whiteBalance == .auto && !camera.isWhiteBalanceCustom)
        #expect(camera.whiteBalanceChipText == "AUTO")
        #expect(camera.activeWhiteBalancePreset == .auto)
    }

    @Test func kelvinAndTintClampToTheirRanges() {
        #expect(CaptureSession.clampedKelvin(100) == 2500)
        #expect(CaptureSession.clampedKelvin(5600) == 5600)
        #expect(CaptureSession.clampedKelvin(20_000) == 9000)
        #expect(CaptureSession.clampedKelvin(.nan) == 2500)
        #expect(CaptureSession.clampedTint(-90) == -50)
        #expect(CaptureSession.clampedTint(12) == 12)
        #expect(CaptureSession.clampedTint(90) == 50)
        #expect(CaptureSession.clampedTint(.nan) == 0)
    }

    @Test func slidersSetAFreeBalanceAndTheChipReadsTheKelvin() throws {
        let camera = try camera()
        camera.setWhiteBalanceKelvin(5600)
        #expect(camera.isWhiteBalanceCustom && camera.activeWhiteBalancePreset == nil)
        #expect(camera.whiteBalanceChipText == "5600K")

        camera.setWhiteBalanceTint(-80)
        #expect(camera.whiteBalanceTint == -50 && camera.whiteBalanceKelvin == 5600)
        camera.setWhiteBalanceKelvin(99_999)
        #expect(camera.whiteBalanceKelvin == 9000)
        #expect(camera.whiteBalanceChipText == "9000K")
    }

    @Test func aPresetMovesTheSlidersToItsValuesAndAutoGoesBack() throws {
        let camera = try camera()
        camera.setWhiteBalance(kelvin: 4321, tint: 7)
        camera.chooseWhiteBalancePreset(.tungsten)
        #expect(!camera.isWhiteBalanceCustom && camera.activeWhiteBalancePreset == .tungsten)
        #expect(camera.whiteBalanceKelvin == 3200 && camera.whiteBalanceTint == 0)
        #expect(camera.whiteBalanceChipText == "3200K")

        camera.chooseWhiteBalancePreset(.auto)
        #expect(camera.whiteBalanceChipText == "AUTO")
        #expect(camera.whiteBalanceKelvin == 3200, "Auto leaves the sliders where they were")
    }

    @Test func everyPresetStaysInsideTheSliderRange() {
        for mode in WBMode.allCases {
            guard let preset = mode.temperatureAndTint else { continue }
            #expect(Constants.Camera.whiteBalanceKelvinRange.contains(preset.temperature), "\(mode.label)")
            #expect(Constants.Camera.whiteBalanceTintRange.contains(preset.tint), "\(mode.label)")
        }
    }

    @Test func chipTextIsPure() {
        #expect(CameraViewModel.whiteBalanceChipText(mode: .auto, isCustom: false, kelvin: 5600) == "AUTO")
        #expect(CameraViewModel.whiteBalanceChipText(mode: .auto, isCustom: true, kelvin: 4999.6) == "5000K")
        #expect(CameraViewModel.whiteBalanceChipText(mode: .cloudy, isCustom: false, kelvin: 6500) == "6500K")
    }

    @Test func gainsClampToOneAndTheDevicesMaximum() {
        let wild = AVCaptureDevice.WhiteBalanceGains(redGain: 0.2, greenGain: 1.5, blueGain: 9.5)
        let clamped = CaptureSession.clampedGains(wild, maxGain: 4)
        #expect(clamped.redGain == 1 && clamped.greenGain == 1.5 && clamped.blueGain == 4)
        let inside = AVCaptureDevice.WhiteBalanceGains(redGain: 1, greenGain: 2, blueGain: 3.9)
        let same = CaptureSession.clampedGains(inside, maxGain: 4)
        #expect(same.redGain == 1 && same.greenGain == 2 && same.blueGain == 3.9)
    }

    @Test func aCameraStartResetsToAutoLikeALaunch() async throws {
        // OPEN: v5-4 — nothing persists. The simulator has no camera, so
        // startCamera stops at the permission check; the reset itself is the
        // same call the launch path makes, exercised through the state it clears.
        let camera = try camera()
        camera.setWhiteBalance(kelvin: 3000, tint: 10)
        camera.setExposureBias(1)
        #expect(!Constants.Camera.persistWhiteBalanceAndExposure)
        let fresh = try self.camera()
        #expect(fresh.whiteBalanceChipText == "AUTO" && fresh.exposureBias == 0)
    }
}

@MainActor
struct ExposureStepTests {

    private func camera() throws -> CameraViewModel {
        let defaults = try makeScratchDefaults()
        return CameraViewModel(defaults: defaults)
    }

    @Test func snapsToTheNearestThirdOfAStop() {
        #expect(CameraViewModel.snappedExposureBias(0) == 0)
        #expect(abs(CameraViewModel.snappedExposureBias(0.3) - 1.0 / 3) < 1e-6)
        #expect(abs(CameraViewModel.snappedExposureBias(0.5) - 2.0 / 3) < 1e-6)
        #expect(abs(CameraViewModel.snappedExposureBias(-0.4) + 1.0 / 3) < 1e-6)
        #expect(abs(CameraViewModel.snappedExposureBias(1.49) - 4.0 / 3) < 1e-6)
        #expect(CameraViewModel.snappedExposureBias(1.0) == 1)
    }

    @Test func clampsToMinusTwoPlusTwo() {
        #expect(CameraViewModel.snappedExposureBias(5) == 2)
        #expect(CameraViewModel.snappedExposureBias(-5) == -2)
        #expect(CameraViewModel.snappedExposureBias(.nan) == 0)
    }

    @Test func thereAreTwelveStepsFromEndToEnd() {
        let range = Constants.Camera.exposureBiasMax - Constants.Camera.exposureBiasMin
        #expect(Int((range / Constants.Camera.exposureStep).rounded()) == 12)
    }

    @Test func readoutShowsSignAndOneDecimal() {
        #expect(CameraViewModel.exposureReadoutText(for: 0) == "0.0")
        #expect(CameraViewModel.exposureReadoutText(for: 1.0 / 3) == "+0.3")
        #expect(CameraViewModel.exposureReadoutText(for: -5.0 / 3) == "-1.7")
        #expect(CameraViewModel.exposureReadoutText(for: 2) == "+2.0")
        #expect(CameraViewModel.exposureReadoutText(for: -0.01) == "0.0")
    }

    @Test func theChipAndTheSwipeShareOneBias() throws {
        let camera = try camera()
        camera.setExposureBias(0.7)
        #expect(abs(camera.exposureBias - 2.0 / 3) < 1e-6)
        #expect(camera.exposureReadout == "+0.7")
        #expect(camera.isExposureIndicatorVisible, "a non-zero bias stays on screen")

        // A swipe continues from the chip's value...
        camera.exposureDragChanged(translationHeight: -Constants.Camera.exposureDragScale / 4)
        #expect(camera.exposureBias > 2.0 / 3)
        // ...and settles on a detent when the finger lifts
        camera.exposureDragEnded()
        let steps = camera.exposureBias * Float(Constants.Camera.exposureStepsPerStop)
        #expect(abs(steps - steps.rounded()) < 1e-4, "settled on a third-stop detent: \(camera.exposureBias)")

        // ...and the chip continues from the swipe's
        camera.stepExposureBias(by: 1)
        #expect(abs(camera.exposureBias * 3 - (steps.rounded() + 1)) < 1e-4)
    }

    @Test func steppingStopsAtTheEnds() throws {
        let camera = try camera()
        camera.stepExposureBias(by: 100)
        #expect(camera.exposureBias == 2)
        camera.stepExposureBias(by: -100)
        #expect(camera.exposureBias == -2)
        camera.stepExposureBias(by: 6)
        #expect(camera.exposureBias == 0)
    }
}
