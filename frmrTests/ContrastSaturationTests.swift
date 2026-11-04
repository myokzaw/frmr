import Foundation
import Testing
import UIKit
@testable import frmr

// F-122-J: the Contrast and Saturation tools. Contrast is part of `ToneStage`;
// Saturation is `SaturationStage`, baked to a small colour cube. These tests
// check the maths, the rendered pipeline on every stock, FilmLook's storage and
// the editor's wiring.

/// Colour blocks and a grey ramp, so both tools have something to act on.
private func testPhoto() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let colours: [UIColor] = [
        UIColor(red: 0.8, green: 0.25, blue: 0.2, alpha: 1), UIColor(red: 0.25, green: 0.6, blue: 0.3, alpha: 1),
        UIColor(red: 0.2, green: 0.35, blue: 0.75, alpha: 1), UIColor(red: 0.85, green: 0.62, blue: 0.5, alpha: 1),
    ]
    return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 64), format: format).image { context in
        for (index, colour) in colours.enumerated() {
            colour.setFill()
            context.fill(CGRect(x: index * 64, y: 0, width: 64, height: 32))
        }
        for level in 0..<256 {
            UIColor(white: CGFloat(level) / 255, alpha: 1).setFill()
            context.fill(CGRect(x: level, y: 32, width: 1, height: 32))
        }
    }
}

private func chroma(_ colour: (r: Double, g: Double, b: Double)) -> Double {
    max(colour.r, colour.g, colour.b) - min(colour.r, colour.g, colour.b)
}

struct ContrastCurveTests {

    @Test func zeroIsIdentity() {
        for index in 0...100 {
            let x = Double(index) / 100
            #expect(ToneStage.apply(x, shadows: 0, highlights: 0, contrast: 0) == x)
        }
    }

    @Test(arguments: [-1, -0.5, 0.25, 0.5, 1] as [Double])
    func curveIsMonotone(contrast: Double) {
        var previous = -Double.infinity
        for index in 0...4000 {
            let out = ToneStage.apply(Double(index) / 4000, shadows: 0, highlights: 0, contrast: contrast)
            #expect(out >= previous, "contrast \(contrast) at \(index)")
            previous = out
        }
    }

    @Test func fullContrastReachesTrueBlackAndPureWhite() {
        #expect(ToneStage.apply(0.04, shadows: 0, highlights: 0, contrast: 1) * 255 < 1)
        #expect(ToneStage.apply(0.96, shadows: 0, highlights: 0, contrast: 1) * 255 > 254)
        #expect(abs(ToneStage.apply(0.5, shadows: 0, highlights: 0, contrast: 1) - 0.5) < 0.0001, "mid grey stays put")
    }

    @Test func lowContrastClosesTheRangeTowardMidGrey() {
        #expect(ToneStage.apply(0, shadows: 0, highlights: 0, contrast: -1) == 0.25)
        #expect(ToneStage.apply(1, shadows: 0, highlights: 0, contrast: -1) == 0.75)
        #expect(ToneStage.apply(0.5, shadows: 0, highlights: 0, contrast: -1) == 0.5)
    }

    @Test func shadowsCanOpenWhatContrastCrushed() {
        let crushed = ToneStage.apply(0.1, shadows: 0, highlights: 0, contrast: 1)
        #expect(ToneStage.apply(0.1, shadows: 1, highlights: 0, contrast: 1) > crushed + 0.05)
    }
}

struct SaturationStageTests {
    private let muted = (r: 0.45, g: 0.55, b: 0.5)
    private let vivid = (r: 0.1, g: 0.9, b: 0.2)

    @Test func zeroIsIdentity() {
        let out = SaturationStage.apply(r: 0.8, g: 0.3, b: 0.2, amount: 0)
        #expect(out.r == 0.8 && out.g == 0.3 && out.b == 0.2)
    }

    @Test func fullyDownIsGrey() {
        let out = SaturationStage.apply(r: 0.8, g: 0.3, b: 0.2, amount: -1)
        #expect(out.r == out.g && out.g == out.b)
        #expect(abs(out.r - (0.2126 * 0.8 + 0.7152 * 0.3 + 0.0722 * 0.2)) < 0.0001)
    }

    @Test func greysStayGreyAtFullBoost() {
        for level in [0, 0.2, 0.5, 0.9, 1] as [Double] {
            let out = SaturationStage.apply(r: level, g: level, b: level, amount: 1)
            #expect(abs(out.r - level) < 1e-9 && abs(out.g - level) < 1e-9 && abs(out.b - level) < 1e-9)
        }
    }

    @Test func mutedColoursGainMoreThanVividOnes() {
        let mutedGain = chroma(SaturationStage.apply(r: muted.r, g: muted.g, b: muted.b, amount: 1)) / chroma(muted)
        let vividGain = chroma(SaturationStage.apply(r: vivid.r, g: vivid.g, b: vivid.b, amount: 1)) / chroma(vivid)
        #expect(mutedGain > 1.5)
        #expect(vividGain < mutedGain)
    }

    @Test func skinGainsLessThanAnEquallyColourfulBlue() {
        let skin = (r: 0.85, g: 0.62, b: 0.5)
        let blue = (r: 0.5, g: 0.62, b: 0.85)
        #expect(SaturationStage.skinWeight(r: skin.r, g: skin.g, b: skin.b) > 0.8)
        #expect(SaturationStage.skinWeight(r: blue.r, g: blue.g, b: blue.b) < 0.01)
        let skinGain = chroma(SaturationStage.apply(r: skin.r, g: skin.g, b: skin.b, amount: 1)) / chroma(skin)
        let blueGain = chroma(SaturationStage.apply(r: blue.r, g: blue.g, b: blue.b, amount: 1)) / chroma(blue)
        #expect(skinGain > 1, "skin still gains a little")
        #expect(skinGain < blueGain - 0.3)
    }

    @Test func aVividOrangeIsNotTreatedAsSkin() {
        #expect(SaturationStage.skinWeight(r: 1, g: 0.5, b: 0) == 0)
    }

    @Test func boostStaysInGamutAndKeepsTheHue() {
        for colour in [vivid, (r: 0.98, g: 0.4, b: 0.1), (r: 0.05, g: 0.05, b: 0.6)] {
            let out = SaturationStage.apply(r: colour.r, g: colour.g, b: colour.b, amount: 1)
            for channel in [out.r, out.g, out.b] { #expect((0...1).contains(channel)) }
            let inGrey = 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
            let outGrey = 0.2126 * out.r + 0.7152 * out.g + 0.0722 * out.b
            #expect(abs(inGrey - outGrey) < 0.0001, "brightness holds")
            #expect(abs((out.r - outGrey) * (colour.b - inGrey) - (out.b - outGrey) * (colour.r - inGrey)) < 0.0001, "hue holds")
        }
    }

    @Test func cubeHasOneEntryPerGridPoint() {
        let data = SaturationStage.cube(amount: 0.5, dimension: 5)
        #expect(data.count == 5 * 5 * 5 * 4 * MemoryLayout<Float>.size)
        #expect(SaturationStage.cachedCube(amount: 0.5) == SaturationStage.cachedCube(amount: 0.5))
    }
}

struct ContrastSaturationRenderTests {
    private static let colourStocks = StripCustomization.FilmStock.allCases.filter { !$0.isMonochrome }

    private func raster(_ look: FilmLook, seed: UInt64 = 1) throws -> Raster {
        try #require(Raster(try ImageProcessor.renderFullLook(of: testPhoto(), look: look, seed: seed)))
    }

    private func pixel(_ raster: Raster, x: Int, y: Int) -> [Int] {
        let offset = (y * raster.width + x) * 4
        return [Int(raster.bytes[offset]), Int(raster.bytes[offset + 1]), Int(raster.bytes[offset + 2])]
    }

    @Test(arguments: StripCustomization.FilmStock.allCases)
    func zeroLeavesEveryStockUnchanged(stock: StripCustomization.FilmStock) throws {
        let plain = try #require(Raster(try ImageProcessor.renderFullLook(of: testPhoto(), stock: stock, seed: 6)))
        var look = FilmLook.stockDefaults(for: stock)
        look.contrast = 0
        look.saturation = 0
        #expect(try raster(look, seed: 6) == plain, "\(stock.label)")
    }

    /// With every default effect on, so grain and light leak are covered too.
    @Test(arguments: colourStocks)
    func fullyDownIsTrulyGrey(stock: StripCustomization.FilmStock) throws {
        var look = FilmLook.stockDefaults(for: stock)
        look.saturation = -100
        look.strengths.lightLeak = 1
        let image = try raster(look)
        for y in stride(from: 2, to: 62, by: 12) {
            for x in stride(from: 4, to: 252, by: 16) {
                let colour = pixel(image, x: x, y: y)
                #expect(colour.max()! - colour.min()! <= 2, "\(stock.label) at \(x),\(y): \(colour)")
            }
        }
    }

    @Test(arguments: colourStocks)
    func boostAddsColour(stock: StripCustomization.FilmStock) throws {
        let base = FilmLook(stock: stock, strengths: .allOff)
        let plain = try raster(base)
        var boosted = base
        boosted.saturation = 100
        let image = try raster(boosted)
        // The red, green and blue blocks
        for x in [32, 96, 160] {
            let before = pixel(plain, x: x, y: 16), after = pixel(image, x: x, y: 16)
            #expect(after.max()! - after.min()! > before.max()! - before.min()!, "\(stock.label) at \(x)")
        }
    }

    @Test(arguments: StripCustomization.FilmStock.allCases.filter(\.isMonochrome))
    func blackAndWhiteStocksIgnoreSaturation(stock: StripCustomization.FilmStock) throws {
        let base = FilmLook(stock: stock, strengths: .allOff)
        var up = base
        up.saturation = 100
        var down = base
        down.saturation = -100
        let plain = try raster(base)
        #expect(try raster(up) == plain && raster(down) == plain, "\(stock.label)")
    }

    @Test func theBlackAndWhiteSwitchIgnoresSaturationToo() throws {
        let base = FilmLook(stock: .portrait400, blackAndWhite: true, strengths: .allOff)
        var up = base
        up.saturation = 100
        #expect(try raster(up) == raster(base))
    }

    @Test(arguments: StripCustomization.FilmStock.allCases)
    func contrastDarkensDarksLightensLightsAndStaysSmooth(stock: StripCustomization.FilmStock) throws {
        let base = FilmLook(stock: stock, strengths: .allOff)
        let plain = try raster(base)
        var high = base
        high.contrast = 100
        let image = try raster(high)
        var low = base
        low.contrast = -100
        let faded = try raster(low)
        #expect(pixel(image, x: 30, y: 48)[1] < pixel(plain, x: 30, y: 48)[1], "\(stock.label)")
        #expect(pixel(image, x: 225, y: 48)[1] > pixel(plain, x: 225, y: 48)[1], "\(stock.label)")
        #expect(pixel(faded, x: 0, y: 48)[1] > pixel(plain, x: 0, y: 48)[1], "\(stock.label)")
        #expect(pixel(faded, x: 255, y: 48)[1] < pixel(plain, x: 255, y: 48)[1], "\(stock.label)")
        for x in 1..<256 {
            #expect(pixel(image, x: x, y: 48)[1] >= pixel(image, x: x - 1, y: 48)[1] - 1, "\(stock.label) at \(x)")
        }
    }

    @Test func worksWithTheStockOffAndIsRepeatable() throws {
        var look = FilmLook.original
        look.contrast = 40
        look.saturation = 60
        #expect(try raster(look) != raster(.original))
        #expect(try raster(look) == raster(look))
    }
}

struct ContrastSaturationLookTests {

    @Test func snapsAndClamps() {
        let look = FilmLook(stock: .daylight200, contrast: 33.4, saturation: -999)
        #expect(look.contrast == 33 && look.saturation == -100)
    }

    @Test func storedFormRoundTripsAndOlderLooksReadAsZero() throws {
        let look = FilmLook(stock: .cine500T, contrast: -40, saturation: 25)
        let data = try #require(FilmLook.encoded(look))
        #expect(FilmLook.decoded(from: data) == look)

        var older = FilmLook(stock: .cine500T)
        older.shadows = 10
        let olderData = try #require(FilmLook.encoded(older))
        let text = String(decoding: olderData, as: UTF8.self)
        #expect(!text.contains("contrast") && !text.contains("saturation"), "an untouched look stores what it always did")
        let decoded = FilmLook.decoded(from: olderData)
        #expect(decoded.contrast == 0 && decoded.saturation == 0)
    }

    @Test func countsAsAnEditAndReachesThePipeline() {
        #expect(FilmLook(stock: .none, contrast: 1).altersPhoto)
        #expect(FilmLook(stock: .none, saturation: -1).altersPhoto)
        let look = FilmLook(stock: .portrait400, contrast: 20, saturation: -30)
        #expect(!look.isStockDefault)
        #expect(look.customization.contrast == 20 && look.customization.saturation == -30)
        #expect(look.with(stock: .daylight200).contrast == 20, "changing stock keeps the edit")
    }
}

@MainActor
struct ContrastSaturationEditorTests {

    private func edit(stock: StripCustomization.FilmStock = .portrait400) -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: testPhoto(), stock: stock)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    @Test func settersSnapReadOutAndReset() {
        let edit = edit()
        #expect(edit.contrastReadout == "0" && edit.saturationReadout == "0")
        edit.setContrast(25.2)
        edit.setSaturation(-40)
        #expect(edit.contrast == 25 && edit.contrastReadout == "+25")
        #expect(edit.saturation == -40 && edit.saturationReadout == "\u{2212}40")
        #expect(edit.isModified && edit.canResetToStockDefaults)
        edit.resetToStockDefaults()
        #expect(edit.contrast == 0 && edit.saturation == 0 && !edit.canResetToStockDefaults)
    }

    @Test func toolIDsRoundTrip() {
        #expect(PhotoEditViewModel.Tool(id: "contrast") == .contrast)
        #expect(PhotoEditViewModel.Tool(id: "saturation") == .saturation)
    }

    @Test func toolBarShowsRings() {
        let look = FilmLook(stock: .portrait400, contrast: 50, saturation: -100)
        let items = PhotoEditView.toolItems(look: look, exposureReadout: "0 EV", contrastReadout: "+50", saturationReadout: "\u{2212}100")
        #expect(items[3].id == "contrast" && items[3].ring == 0.5 && items[3].value == "+50")
        #expect(items[4].id == "saturation" && items[4].ring == -1)
    }

    @Test func blackAndWhiteHidesSaturationButKeepsContrast() {
        let colour = PhotoEditView.toolItems(look: FilmLook(stock: .portrait400), exposureReadout: "0 EV").map(\.id)
        #expect(colour.contains("saturation"))
        let switched = PhotoEditView.toolItems(look: FilmLook(stock: .portrait400, blackAndWhite: true), exposureReadout: "0 EV").map(\.id)
        #expect(!switched.contains("saturation") && switched.contains("contrast"))
        let mono = StripCustomization.FilmStock.allCases.first(where: \.isMonochrome)!
        let monoIDs = PhotoEditView.toolItems(look: FilmLook(stock: mono), exposureReadout: "0 EV").map(\.id)
        #expect(!monoIDs.contains("saturation") && monoIDs.contains("contrast"))
    }

    @Test func leavesTheSaturationToolWhenTheLookTurnsBlackAndWhite() {
        let edit = edit()
        edit.select(tool: .saturation)
        edit.setSaturation(20)
        #expect(edit.tool == .saturation)
        edit.setBlackAndWhite(true)
        #expect(edit.tool == .film)
        #expect(edit.saturation == 20, "the value waits in case colour comes back")
    }
}

struct ContrastSaturationSymbolTests {
    @Test func toolBarGlyphsExist() {
        let items = PhotoEditView.toolItems(look: FilmLook(stock: .portrait400), exposureReadout: "0 EV")
        for id in ["contrast", "saturation"] {
            let symbol = items.first { $0.id == id }?.systemImage ?? ""
            #expect(UIImage(systemName: symbol) != nil, "\(id): \(symbol)")
        }
    }
}
