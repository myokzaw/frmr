import SwiftUI

/// Representative colours of a film stock (v5.2 S8): fixed reference patches
/// pushed through the stock's own film chain, so a dial cell can show how the
/// stock behaves (Cine's cool shadows, Mono's greys), not just its code.
///
/// Pure maths on the same `FilmChain` the cube is built from, on the stock's
/// default print, at 0 EV. Deterministic and cached.
nonisolated enum FilmSwatch {
    /// 2–3 colours: the skin, sky and foliage patches through the stock.
    /// Stock Off returns the patches untouched.
    static func colors(for stock: StripCustomization.FilmStock) -> [Color] {
        rgbValues(for: stock).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: 1) }
    }

    /// The same colours as gamma-encoded sRGB components (testable).
    static func rgbValues(for stock: StripCustomization.FilmStock) -> [(r: Double, g: Double, b: Double)] {
        if let cached = cache.value(for: stock) { return cached }
        let computed = compute(stock)
        cache.insert(computed, for: stock)
        return computed
    }

    private static func compute(_ stock: StripCustomization.FilmStock) -> [(r: Double, g: Double, b: Double)] {
        let patches = Constants.ImageProcessing.Swatch.patches
        guard let negative = stock.negative, let print = stock.defaultPrint?.profile else { return patches }
        let chain = FilmChain(negative: negative, print: print, monochrome: stock.isMonochrome)
        return patches.map { patch in
            let out = chain.render(
                r: FilmModel.linear(fromSRGB: patch.r),
                g: FilmModel.linear(fromSRGB: patch.g),
                b: FilmModel.linear(fromSRGB: patch.b)
            )
            return (FilmModel.sRGB(fromLinear: out.r), FilmModel.sRGB(fromLinear: out.g), FilmModel.sRGB(fromLinear: out.b))
        }
    }

    private static let cache = SwatchCache()
}

nonisolated private final class SwatchCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [StripCustomization.FilmStock: [(r: Double, g: Double, b: Double)]] = [:]

    func value(for stock: StripCustomization.FilmStock) -> [(r: Double, g: Double, b: Double)]? {
        lock.lock()
        defer { lock.unlock() }
        return entries[stock]
    }

    func insert(_ values: [(r: Double, g: Double, b: Double)], for stock: StripCustomization.FilmStock) {
        lock.lock()
        defer { lock.unlock() }
        entries[stock] = values
    }
}
