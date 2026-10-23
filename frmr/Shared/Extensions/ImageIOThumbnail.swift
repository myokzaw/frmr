import Foundation
import ImageIO
import UIKit

/// Decodes a photo file straight to a small, upright bitmap with ImageIO,
/// so a thumbnail never holds the 12-48 MP original in memory.
nonisolated enum ImageIOThumbnail {
    /// The file decoded upright (EXIF orientation applied, tagged `.up`)
    /// with its long side at most `maxPixelSize`. nil when unreadable.
    static func load(contentsOf url: URL, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize >= 1, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Like `load(contentsOf:maxPixelSize:)`, sized so the result still
    /// covers `coveringPixelSize` (the render shrinks it to exactly that).
    /// Never upscales: a small original loads at its own size.
    static func load(contentsOf url: URL, coveringPixelSize: CGSize) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        let scale = min(1, max(coveringPixelSize.width / width, coveringPixelSize.height / height))
        // Headroom so the render's own resize still has pixels to cover with
        let longSide = Int((max(width, height) * scale * 1.1).rounded(.up)) + 2
        return load(contentsOf: url, maxPixelSize: longSide)
    }
}
