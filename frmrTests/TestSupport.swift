import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Shared test helpers. Search here before writing a new pixel reader or image builder.

// Minimal RGBA pixel reader so the rendering tests can assert on real output
// rather than on the code that produced it.
struct PixelBuffer: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage)
    }

    init?(_ cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = raw
    }

    func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]))
    }

    /// Variance of per-pixel luminance — how much grain is present.
    var luminanceVariance: Double {
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                values.append(0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    var channelMeans: (r: Double, g: Double, b: Double) {
        var totals = (r: 0.0, g: 0.0, b: 0.0)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                totals.r += pixel.r
                totals.g += pixel.g
                totals.b += pixel.b
            }
        }
        let count = Double(width * height)
        return (totals.r / count, totals.g / count, totals.b / count)
    }
}

func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

/// A throwaway UserDefaults suite, so a test never touches the app's real settings.
func makeScratchDefaults() throws -> UserDefaults {
    let suite = "frmr.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

// MARK: Core Image / float-context helpers (FilmLook and effect tests)

let lookContext = CIContext(options: [.workingFormat: CIFormat.RGBAh])
let lookSRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

struct Raster: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(_ image: CIImage) {
        guard let cgImage = lookContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: lookSRGB) else {
            return nil
        }
        self.init(cgImage)
    }

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage)
    }

    init?(_ cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        var raw = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: lookSRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = raw
    }

    func luma(_ x: Int, _ y: Int) -> Double {
        let offset = (y * width + x) * 4
        return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / 3
    }

    var variance: Double {
        var sum = 0.0, squares = 0.0
        let count = Double(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = luma(x, y)
                sum += value
                squares += value * value
            }
        }
        let mean = sum / count
        return squares / count - mean * mean
    }

    var mean: Double {
        var sum = 0.0
        for y in 0..<height { for x in 0..<width { sum += luma(x, y) } }
        return sum / Double(width * height)
    }
}

func flatImage(_ white: CGFloat, size: CGSize = CGSize(width: 120, height: 96)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

func ciFlat(_ white: CGFloat, size: CGSize = CGSize(width: 64, height: 64)) -> CIImage {
    CIImage(color: CIColor(red: white, green: white, blue: white)).cropped(to: CGRect(origin: .zero, size: size))
}
