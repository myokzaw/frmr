import CoreImage
import Foundation
import Testing
import UIKit
@testable import frmr

// F-122-C: the Shadows and Highlights tools. The maths is `ToneStage` (one
// monotone curve on the printed picture, after the film cube); these tests
// check the curve itself, the rendered pipeline on every stock, FilmLook's
// storage and the editor's wiring.

private let stocks = StripCustomization.FilmStock.allCases

/// A horizontal grey ramp, one column per 8-bit input level 0...255.
private func rampImage() -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 4), format: format).image { context in
        for level in 0..<256 {
            UIColor(white: CGFloat(level) / 255, alpha: 1).setFill()
            context.fill(CGRect(x: level, y: 0, width: 1, height: 4))
        }
    }
}

/// Red/green/blue of every ramp column after `look` (effects off, so only
/// the tone is under test).
private func renderedRamp(stock: StripCustomization.FilmStock, shadows: Double = 0, highlights: Double = 0) throws -> [[Int]] {
    let look = FilmLook(stock: stock, strengths: .allOff, shadows: shadows, highlights: highlights)
    let rendered = try ImageProcessor.renderFullLook(of: rampImage(), look: look, seed: 1)
    let raster = try #require(Raster(rendered))
    return (0..<256).map { x in
        let offset = (1 * raster.width + x) * 4
        return [Int(raster.bytes[offset]), Int(raster.bytes[offset + 1]), Int(raster.bytes[offset + 2])]
    }
}

struct ToneStageCurveTests {

    @Test func zeroIsTheIdentity() {
        for value in stride(from: 0.0, through: 1.0, by: 0.01) {
            #expect(ToneStage.apply(value, shadows: 0, highlights: 0) == value)
        }
    }

    @Test(arguments: [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (0.5, -0.5)])
    func curveIsMonotone(shadows: Double, highlights: Double) {
        var previous = -Double.infinity
        for index in 0...4000 {
            let out = ToneStage.apply(Double(index) / 4000, shadows: shadows, highlights: highlights)
            #expect(out >= previous, "s \(shadows) h \(highlights) at \(index)")
            previous = out
        }
    }

    @Test func directionsAreRespected() {
        for index in 0...1000 {
            let x = Double(index) / 1000
            #expect(ToneStage.apply(x, shadows: 1, highlights: 0) >= x)
            #expect(ToneStage.apply(x, shadows: -1, highlights: 0) <= x)
            #expect(ToneStage.apply(x, shadows: 0, highlights: -1) <= x)
            #expect(ToneStage.apply(x, shadows: 0, highlights: 1) >= x)
        }
    }

    @Test func eachToolStaysOnItsSideOfMidGrey() {
        for index in 0...1000 {
            let x = Double(index) / 1000
            if x >= ToneStage.pivot {
                #expect(ToneStage.apply(x, shadows: 1, highlights: 0) == x)
                #expect(ToneStage.apply(x, shadows: -1, highlights: 0) == x)
            } else {
                #expect(ToneStage.apply(x, shadows: 0, highlights: 1) == x)
                #expect(ToneStage.apply(x, shadows: 0, highlights: -1) == x)
            }
        }
    }

    @Test func fullyDeepenedShadowsKeepDeepTonesApart() {
        let a = ToneStage.apply(0.01, shadows: -1, highlights: 0)
        let b = ToneStage.apply(0.03, shadows: -1, highlights: 0)
        #expect(a > 0 && b - a > 0.005, "No clipping into one value")
    }

    @Test func whiteStaysNearWhite() {
        #expect(ToneStage.apply(1, shadows: 0, highlights: 1) == 1)
        #expect(ToneStage.apply(1, shadows: 0, highlights: -1) > 0.9)
    }
}

struct ShadowsHighlightsRenderTests {

    @Test(arguments: stocks, [-100.0, 100.0])
    func outputIsMonotoneOnEveryStock(stock: StripCustomization.FilmStock, amount: Double) throws {
        for (shadows, highlights) in [(amount, 0.0), (0.0, amount), (amount, amount)] {
            let ramp = try renderedRamp(stock: stock, shadows: shadows, highlights: highlights)
            for channel in 0..<3 {
                for x in 1..<256 {
                    // One 8-bit level of slack for rounding
                    #expect(ramp[x][channel] >= ramp[x - 1][channel] - 1, "\(stock.label) s \(shadows) h \(highlights) at \(x)")
                }
            }
        }
    }

    @Test(arguments: stocks)
    func toolsMoveTheRightTonesTheRightWay(stock: StripCustomization.FilmStock) throws {
        let base = try renderedRamp(stock: stock)
        let shadowsUp = try renderedRamp(stock: stock, shadows: 100)
        let shadowsDown = try renderedRamp(stock: stock, shadows: -100)
        let highlightsUp = try renderedRamp(stock: stock, highlights: 100)
        let highlightsDown = try renderedRamp(stock: stock, highlights: -100)
        // The pivot is level 128; a couple of levels of
        // tolerance for rounding and the lookup table's interpolation
        let mid = Int((ToneStage.pivot * 255).rounded())
        for x in 0..<256 {
            for channel in 0..<3 {
                let b = base[x][channel]
                #expect(shadowsUp[x][channel] >= b - 1, "\(stock.label) +shadows darkened \(x)")
                #expect(shadowsDown[x][channel] <= b + 1, "\(stock.label) -shadows brightened \(x)")
                #expect(highlightsDown[x][channel] <= b + 1, "\(stock.label) -highlights brightened \(x)")
                #expect(highlightsUp[x][channel] >= b - 1, "\(stock.label) +highlights darkened \(x)")
            }
        }
        // Shadows barely moves what the print puts at or above mid grey;
        // Highlights barely moves what it puts at or below
        for x in 0..<256 {
            let printed = base[x][1]
            if printed >= mid + 2 {
                #expect(abs(shadowsUp[x][1] - printed) <= 2 && abs(shadowsDown[x][1] - printed) <= 2, "\(stock.label) shadows moved \(printed)")
            }
            if printed <= mid - 2 {
                #expect(abs(highlightsUp[x][1] - printed) <= 2 && abs(highlightsDown[x][1] - printed) <= 2, "\(stock.label) highlights moved \(printed)")
            }
        }
    }

    @Test(arguments: stocks)
    func deepShadowsStayDistinctAtMinusHundred(stock: StripCustomization.FilmStock) throws {
        let ramp = try renderedRamp(stock: stock, shadows: -100)
        // Inputs 3 and 8 of 255 (about linear 0.001 and 0.003)
        #expect(ramp[8][1] > ramp[3][1] || ramp[3][1] == 0 && ramp[8][1] > 0, "\(stock.label)")
        #expect(ramp[8][1] >= 1, "\(stock.label) black is not crushed to nothing")
    }

    @Test(arguments: stocks)
    func renderingIsDeterministic(stock: StripCustomization.FilmStock) throws {
        let a = try renderedRamp(stock: stock, shadows: 40, highlights: -60)
        let b = try renderedRamp(stock: stock, shadows: 40, highlights: -60)
        #expect(a == b)
    }

    @Test func stockOffStillAppliesBothTools() throws {
        let base = try renderedRamp(stock: .none, shadows: 0, highlights: 0)
        let shadows = try renderedRamp(stock: .none, shadows: 100)
        let highlights = try renderedRamp(stock: .none, highlights: -100)
        #expect(shadows[40][1] > base[40][1] + 5)
        #expect(highlights[220][1] < base[220][1] - 5)
    }
}

struct ShadowsHighlightsLookTests {

    @Test func snapsClampsAndIgnoresNaN() {
        #expect(FilmLook.snappedTone(24.6) == 25)
        #expect(FilmLook.snappedTone(-250) == -100)
        #expect(FilmLook.snappedTone(250) == 100)
        #expect(FilmLook.snappedTone(.nan) == 0)
        #expect(FilmLook.snappedTone(.infinity) == 0)
        let look = FilmLook(stock: .daylight200, shadows: 33.4, highlights: -999)
        #expect(look.shadows == 33 && look.highlights == -100)
    }

    @Test func codableRoundTripsAndOldLooksReadZero() throws {
        let look = FilmLook(stock: .cine500T, shadows: -40, highlights: 25)
        let decoded = try JSONDecoder().decode(FilmLook.self, from: JSONEncoder().encode(look))
        #expect(decoded == look && decoded.shadows == -40 && decoded.highlights == 25)

        let old = try JSONDecoder().decode(FilmLook.self, from: Data(#"{"stock":"cine500T","exposure":1}"#.utf8))
        #expect(old.shadows == 0 && old.highlights == 0)
    }

    @Test func eitherToolAltersThePhotoEvenWithStockOff() {
        #expect(!FilmLook.original.altersPhoto)
        #expect(FilmLook(stock: .none, shadows: 1).altersPhoto)
        #expect(FilmLook(stock: .none, highlights: -1).altersPhoto)
    }

    @Test func resetToStockDefaultsAndCustomizationCarryThem() {
        let look = FilmLook(stock: .portrait400, shadows: 20, highlights: -30)
        #expect(!look.isStockDefault)
        #expect(look.customization.shadows == 20 && look.customization.highlights == -30)
        #expect(FilmLook(stock: .portrait400).isStockDefault)
    }
}

@MainActor
struct ShadowsHighlightsEditorTests {

    private func edit() -> PhotoEditViewModel {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        let edit = PhotoEditViewModel(preview: image, stock: .portrait400)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    @Test func toolsFollowExposureInOrder() {
        let ids = PhotoEditViewModel.Tool.allTools.map(\.id)
        #expect(Array(ids.prefix(8)) == ["exposure", "shadows", "highlights", "contrast", "saturation", "crop", "film", "print"])
        #expect(PhotoEditViewModel.Tool(id: "shadows") == .shadows && PhotoEditViewModel.Tool(id: "highlights") == .highlights)
    }

    @Test func settersSnapReadOutAndReset() {
        let edit = edit()
        #expect(edit.shadowsReadout == "0" && edit.highlightsReadout == "0")
        edit.setShadows(25.2)
        edit.setHighlights(-40)
        #expect(edit.shadows == 25 && edit.shadowsReadout == "+25")
        #expect(edit.highlights == -40 && edit.highlightsReadout == "\u{2212}40")
        #expect(edit.isModified && edit.canResetToStockDefaults)
        edit.setShadows(900)
        #expect(edit.shadows == 100)
        edit.resetToStockDefaults()
        #expect(edit.shadows == 0 && edit.highlights == 0 && !edit.canResetToStockDefaults)
    }

    @Test func toolBarShowsRingsAndHints() {
        let look = FilmLook(stock: .portrait400, shadows: 50, highlights: -100)
        let items = PhotoEditView.toolItems(look: look, exposureReadout: "0 EV", shadowsReadout: "+50", highlightsReadout: "\u{2212}100")
        #expect(items[1].id == "shadows" && items[1].ring == 0.5 && items[1].value == "+50")
        #expect(items[2].id == "highlights" && items[2].ring == -1)
        #expect(items[1].hint == "Lift or deepen the shadows" && items[2].hint == "Recover or brighten the highlights")
        let plain = PhotoEditView.toolItems(look: .stockDefaults(for: .portrait400), exposureReadout: "0 EV")
        #expect(plain[1].ring == nil && plain[2].ring == nil)
    }

    @Test func scrubberScaleHasFirmTicksAndFiveStepAccessibility() {
        let scale = ScrubberScale.tone
        let firm: (Double) -> Bool = { value in
            let index = Int(value - scale.range.lowerBound)
            return ScrubberMath.tickKind(at: index, in: scale.range, step: scale.step, hapticStep: scale.majorStep, reference: 0, firmStep: scale.firmStep) == .reference
        }
        #expect(firm(0) && firm(50) && firm(-50) && !firm(10) && !firm(49))
        #expect(scale.accessibilityStep == 5)
    }
}
