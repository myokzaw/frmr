import UIKit

/// Small renders of one photo in each film stock or each print (v5.2 M5),
/// for the editor's pickers. Pure and off-main-safe: the view model owns
/// scheduling and caching.
nonisolated enum FilmPreviewThumbnails {
    /// The photo upright and shrunk (never enlarged) to the smallest size
    /// that covers `pixelSize`. Cheap to re-render looks from.
    static func source(from photo: UIImage, coveringPixelSize pixelSize: CGSize) -> UIImage {
        let upright = photo.size
        guard upright.width > 0, upright.height > 0, pixelSize.width >= 1, pixelSize.height >= 1 else { return photo }
        let pixelsWide = upright.width * photo.scale
        let pixelsHigh = upright.height * photo.scale
        let scale = min(1, max(pixelSize.width / pixelsWide, pixelSize.height / pixelsHigh))
        let target = CGSize(width: max(1, (pixelsWide * scale).rounded()), height: max(1, (pixelsHigh * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// `source` through each stock, the rest of `look` kept (a print the
    /// stock can't use falls back to its default).
    static func stockPreviews(
        of source: UIImage, look: FilmLook, seed: UInt64
    ) -> [StripCustomization.FilmStock: UIImage] {
        var result: [StripCustomization.FilmStock: UIImage] = [:]
        for stock in StripCustomization.FilmStock.allCases {
            if let image = render(source, look: look.with(stock: stock), seed: seed) { result[stock] = image }
        }
        return result
    }

    /// `source` on each print the look's stock offers; empty for Off.
    static func printPreviews(
        of source: UIImage, look: FilmLook, seed: UInt64
    ) -> [StripCustomization.PrintStock: UIImage] {
        var result: [StripCustomization.PrintStock: UIImage] = [:]
        for print in look.stock.availablePrints {
            var printed = look
            printed.printStock = print
            if let image = render(source, look: printed, seed: seed) { result[print] = image }
        }
        return result
    }

    /// `source` rendered in exactly `look`; nil if the render fails.
    static func lookPreview(of source: UIImage, look: FilmLook, seed: UInt64) -> UIImage? {
        render(source, look: look, seed: seed)
    }

    private static func render(_ source: UIImage, look: FilmLook, seed: UInt64) -> UIImage? {
        do {
            return try ImageProcessor.renderFullLook(of: source, look: look, seed: seed)
        } catch {
            print("[FilmPreviewThumbnails] Preview render failed: \(error)")
            return nil
        }
    }
}
