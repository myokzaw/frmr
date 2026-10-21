import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Camera gesture mappings, chrome rotation, white balance list and the camera film stock control.

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
}

// MARK: - v4 F9: camera film stock control

@MainActor
struct CameraFilmStockTests {

    @Test func chipCodesMatchTheSpec() {
        #expect(StripCustomization.FilmStock.allCases.map(\.shortCode) == [
            "OFF", "D200", "P400", "C500", "S100", "M400", "M3.2K",
        ])
    }

    @Test func stockDefaultsToOffAndPersistsSeparatelyFromTheStrip() throws {
        let defaults = try makeScratchDefaults()
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
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
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
}
