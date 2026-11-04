import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The picked file's bytes, in the best form the pick offers: a RAW
/// (DNG/ProRAW) when it has one, else its image. The order matters: the
/// first representation the item supports wins.
nonisolated struct PickedImageData: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .rawImage) { PickedImageData(data: $0) }
        DataRepresentation(importedContentType: .image) { PickedImageData(data: $0) }
    }
}

/// Turns a gallery pick into the editor's working photo (F-122-E): RAW goes
/// through the camera's own development, everything else is decoded with its
/// orientation applied. Either way the result is at most
/// `Constants.GalleryImport.maxLongSide` and carries no metadata (a decoded
/// bitmap has none, and `strippedJPEGData` writes only the orientation).
nonisolated enum GalleryImportDecoder {
    enum Path: Equatable {
        case raw
        case standard
    }

    static func path(forContentTypes types: [UTType]) -> Path {
        types.contains { $0.conforms(to: .rawImage) } ? .raw : .standard
    }

    static func path(forTypeIdentifier identifier: String?) -> Path {
        guard let identifier, let type = UTType(identifier) else { return .standard }
        return path(forContentTypes: [type])
    }

    /// Decided from the bytes, not the picker's claim.
    static func path(forData data: Data) -> Path {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return .standard }
        return path(forTypeIdentifier: CGImageSourceGetType(source) as String?)
    }

    /// Loads one pick: its data, then the decode, off the main actor. Any
    /// failure is an `AppError` (`importFailed` unless the RAW path says more).
    static func load(_ item: PhotosPickerItem) async throws -> UIImage {
        do {
            guard let picked = try await item.loadTransferable(type: PickedImageData.self) else {
                throw AppError.importFailed
            }
            return try await Task.detached(priority: .userInitiated) {
                try decode(picked.data)
            }.value
        } catch let error as AppError {
            throw error
        } catch {
            print("[Import] \(error.localizedDescription)")
            throw AppError.importFailed
        }
    }

    static func decode(_ data: Data, maxLongSide: Int = Constants.GalleryImport.maxLongSide) throws -> UIImage {
        switch path(forData: data) {
        case .raw:
            return downscaled(try ImageProcessor.process(rawData: data), maxLongSide: maxLongSide)
        case .standard:
            return try decodeStandard(data, maxLongSide: maxLongSide)
        }
    }

    /// HEIC/JPEG/PNG: upright pixels (orientation applied, never through
    /// `CIImage(image:)`), shrunk by ImageIO while decoding so a 48 MP
    /// original is never held at full size. Never upscales.
    static func decodeStandard(_ data: Data, maxLongSide: Int) throws -> UIImage {
        guard
            maxLongSide >= 1,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw AppError.importFailed }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxLongSide)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.importFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// `image` with its long side at most `maxLongSide`, orientation tag kept
    /// (the RAW path hands back sensor pixels plus a tag). Never upscales.
    static func downscaled(_ image: UIImage, maxLongSide: Int) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let longSide = max(cgImage.width, cgImage.height)
        guard maxLongSide >= 1, longSide > maxLongSide else { return image }
        let factor = Double(maxLongSide) / Double(longSide)
        let width = max(Int((Double(cgImage.width) * factor).rounded()), 1)
        let height = max(Int((Double(cgImage.height) * factor).rounded()), 1)
        guard
            let space = cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return image }
        return UIImage(cgImage: scaled, scale: 1, orientation: image.imageOrientation)
    }

    /// JPEG data holding the pixels and the orientation tag and nothing else:
    /// no GPS, EXIF, TIFF or maker data, so the Roll file and everything
    /// exported from it is private.
    static func strippedJPEGData(from image: UIImage, quality: Double) throws -> Data {
        guard let cgImage = image.cgImage else { throw AppError.importFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw AppError.importFailed }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: ImageProcessor.cgOrientation(from: image.imageOrientation).rawValue,
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError.importFailed }
        return data as Data
    }
}
