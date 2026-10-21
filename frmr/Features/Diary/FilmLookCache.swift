import Foundation
import UIKit

/// In-memory cache of photos rendered through their stock for display
/// (v4 F11): diary thumbnails, the entry viewer and the editor header.
/// The originals on disk are never touched.
///
/// OPEN: v4-11 — rendered copies are not persisted; the cache is memory
/// only and capped by Constants.Diary.displayCacheCostLimitBytes.
/// NSCache is thread-safe, so lookups and inserts happen on whichever
/// thread rendered.
nonisolated final class FilmLookCache: @unchecked Sendable {
    static let shared = FilmLookCache()

    private let cache = NSCache<Key, UIImage>()

    init(costLimitBytes: Int = Constants.Diary.displayCacheCostLimitBytes) {
        cache.totalCostLimit = costLimitBytes
    }

    /// The cached render for this (photo id, stock, pixel size), if any.
    func cachedImage(id: UUID, stock: StripCustomization.FilmStock, pixelSize: CGSize) -> UIImage? {
        cache.object(forKey: Key(id: id, stock: stock, pixelSize: pixelSize))
    }

    /// The photo through its stock at `pixelSize` (upright pixels the view
    /// draws into; the render covers it). Runs the render on the calling
    /// thread, so call it off the main actor. Off returns `loadPhoto()`'s
    /// image itself. nil when the photo can't be loaded.
    ///
    /// - Parameter loadPhoto: only called on a cache miss, so a hit never
    ///   reads the file.
    func image(
        id: UUID,
        stock: StripCustomization.FilmStock,
        seed: UInt64,
        pixelSize: CGSize,
        loadPhoto: () -> UIImage?
    ) -> UIImage? {
        let key = Key(id: id, stock: stock, pixelSize: pixelSize)
        if let cached = cache.object(forKey: key) { return cached }
        guard let photo = loadPhoto() else { return nil }

        let rendered: UIImage
        do {
            rendered = try ImageProcessor.renderFullLook(
                of: photo, stock: stock, seed: seed, coveringPixelSize: pixelSize
            )
        } catch {
            // Display only: the original is still a faithful picture of the
            // entry, and an alert per thumbnail would bury the screen. The
            // failure is logged, the original is shown, nothing is cached.
            print("[FilmLookCache] Film look render failed for \(id); showing the original: \(error)")
            return photo
        }
        cache.setObject(rendered, forKey: key, cost: Self.cost(of: rendered))
        return rendered
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private final class Key: NSObject {
        let id: UUID
        let stock: StripCustomization.FilmStock
        let width: Int
        let height: Int

        init(id: UUID, stock: StripCustomization.FilmStock, pixelSize: CGSize) {
            self.id = id
            self.stock = stock
            self.width = Int(pixelSize.width.rounded())
            self.height = Int(pixelSize.height.rounded())
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(id)
            hasher.combine(stock)
            hasher.combine(width)
            hasher.combine(height)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return id == other.id && stock == other.stock && width == other.width && height == other.height
        }
    }
}
