import Foundation
import Testing
@testable import frmr

// F-122-A: film model 2 opens the shadows and lifts the blacks a little,
// without going back to the grey, milky look v4 removed
// (research/v4-film-reference-calibration.md §1). These pin the direction
// and the ordering of the v2 numbers; the exact look is judged on the
// before/after sheets (FilmStockSampleSheetTests).
struct FilmModelV2ShadowTests {

    private typealias Film = Constants.ImageProcessing.Film
    private typealias Stock = StripCustomization.FilmStock
    private typealias PrintStock = StripCustomization.PrintStock

    private static let v1 = FilmModelParameters.forVersion(1)
    private static let v2 = FilmModelParameters.forVersion(2)
    private static let colourAndMonoStocks: [Stock] = [.daylight200, .portrait400, .cine500T, .slide100, .mono400, .mono3200]

    /// How far mid grey and up may move between v1 and v2, sRGB/255 (the
    /// black target changes the affine white/black remap slightly).
    private static let midAndHighlightTolerance = 4.0

    private static func chain(_ stock: Stock, _ printStock: PrintStock, _ parameters: FilmModelParameters) -> FilmChain {
        FilmChain(
            negative: parameters.negative(for: stock)!, print: parameters.print(for: printStock),
            monochrome: false, toeExponent: parameters.shadowToeExponent
        )
    }

    /// Encoded luminance of a neutral linear input, in /255.
    private static func output(_ chain: FilmChain, _ input: Double) -> Double {
        let out = chain.render(r: input, g: input, b: input)
        return FilmModel.sRGB(fromLinear: Film.Spectral.panchromatic.luminance(r: out.r, g: out.g, b: out.b)) * 255
    }

    private static func defaultChain(_ stock: Stock, _ parameters: FilmModelParameters) -> FilmChain {
        chain(stock, stock.defaultPrint!, parameters)
    }

    @Test func everyPrintsBlackIsLighterInV2() {
        for printStock in PrintStock.allCases {
            let before = Self.v1.print(for: printStock).blackTarget * 255
            let after = Self.v2.print(for: printStock).blackTarget * 255
            #expect(after > before, "\(printStock): \(before) -> \(after)")
            for stock in Self.colourAndMonoStocks {
                let black1 = Self.output(Self.chain(stock, printStock, Self.v1), 0)
                let black2 = Self.output(Self.chain(stock, printStock, Self.v2), 0)
                #expect(black2 > black1 + 1, "\(stock.label) on \(printStock): black \(black1) -> \(black2)")
            }
        }
    }

    @Test func printOrderHoldsInV2() {
        let targets = [PrintStock.projection, .cinema, .lab, .matte].map { Self.v2.print(for: $0).blackTarget }
        #expect(targets == targets.sorted() && Set(targets).count == 4, "Projection < Cinema < Lab < Matte: \(targets.map { $0 * 255 })")
        for stock in Self.colourAndMonoStocks {
            let blacks = [PrintStock.projection, .cinema, .lab, .matte].map { Self.output(Self.chain(stock, $0, Self.v2), 0) }
            #expect(blacks == blacks.sorted() && Set(blacks.map { ($0 * 10).rounded() }).count == 4, "\(stock.label): \(blacks)")
        }
    }

    /// Mean output over linear input 0.02–0.05 (the deep shadows), /255.
    private static func shadowOpenness(_ stock: Stock, _ parameters: FilmModelParameters) -> Double {
        let inputs = [0.02, 0.03, 0.04, 0.05]
        let chain = defaultChain(stock, parameters)
        return inputs.map { output(chain, $0) }.reduce(0, +) / Double(inputs.count)
    }

    @Test func stockOrderHoldsForShadowOpenness() {
        let deepestFirst: [Stock] = [.slide100, .mono3200, .cine500T, .mono400, .daylight200, .portrait400]
        let values = deepestFirst.map { Self.shadowOpenness($0, Self.v2) }
        for (index, pair) in zip(values, values.dropFirst()).enumerated() {
            #expect(pair.1 > pair.0 + 1, "\(deepestFirst[index].label) \(pair.0) vs \(deepestFirst[index + 1].label) \(pair.1)")
        }
    }

    @Test func everyStockOpensItsShadowsInV2() {
        for stock in Self.colourAndMonoStocks {
            let before = Self.shadowOpenness(stock, Self.v1)
            let after = Self.shadowOpenness(stock, Self.v2)
            #expect(after > before + 4, "\(stock.label): \(before) -> \(after)")
        }
    }

    @Test func blackStaysBelowTheAntiMilkyCeilingOnEachDefaultPrint() {
        for stock in Self.colourAndMonoStocks {
            let black = Self.output(Self.defaultChain(stock, Self.v2), 0)
            #expect(black <= Film.ModelV2.blackCeiling, "\(stock.label): black \(black)/255")
        }
    }

    @Test func outputIsMonotonicOnEveryStockAndPrint() {
        for stock in Self.colourAndMonoStocks {
            for printStock in PrintStock.allCases {
                for mono in [false, true] {
                    let chain = FilmChain(
                        negative: Self.v2.negative(for: stock)!, print: Self.v2.print(for: printStock),
                        monochrome: mono, toeExponent: Self.v2.shadowToeExponent
                    )
                    var previous = chain.render(r: 0, g: 0, b: 0)
                    for step in 1...512 {
                        let v = FilmModel.linear(fromSRGB: Double(step) / 512)
                        let next = chain.render(r: v, g: v, b: v)
                        #expect(next.r > previous.r && next.g > previous.g && next.b > previous.b,
                                "\(stock.label) on \(printStock), mono \(mono), at \(v)")
                        previous = next
                    }
                }
            }
        }
    }

    @Test func midGreyAndHighlightsStayCloseToV1() {
        for stock in Self.colourAndMonoStocks {
            for input in [Film.midGrey, 0.35, 0.6, 1.0] {
                let before = Self.output(Self.defaultChain(stock, Self.v1), input)
                let after = Self.output(Self.defaultChain(stock, Self.v2), input)
                #expect(abs(after - before) <= Self.midAndHighlightTolerance, "\(stock.label) at \(input): \(before) -> \(after)")
            }
        }
    }

    @Test func v1ToeIsUnchangedByTheLiftParameter() {
        for stock in Self.colourAndMonoStocks {
            #expect(Self.v1.negative(for: stock)?.shadowLift == 0, "\(stock.label)")
        }
    }
}
