import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Strip screen controls: which controls show, As shot vs the strip-wide override.

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
