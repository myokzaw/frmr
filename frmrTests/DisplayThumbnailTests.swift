import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import frmr

struct DisplayThumbnailTests {

    /// Writes a JPEG of raw size `width` x `height` carrying an EXIF orientation tag.
    private static func writeJPEG(width: Int, height: Int, exifOrientation: Int) throws -> URL {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()
        )
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let cgImage = try #require(image.cgImage)
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: exifOrientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func portraitIsUprightAndNoLargerThanRequested() throws {
        // Raw 400x200 tagged "right" (6) displays as 200x400 portrait
        let url = try Self.writeJPEG(width: 400, height: 200, exifOrientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(ImageIOThumbnail.load(contentsOf: url, maxPixelSize: 100))
        let cg = try #require(image.cgImage)
        #expect(image.imageOrientation == .up)
        #expect(max(cg.width, cg.height) <= 100)
        #expect(cg.height > cg.width)
    }

    @Test func landscapeIsUprightAndNoLargerThanRequested() throws {
        let url = try Self.writeJPEG(width: 400, height: 200, exifOrientation: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(ImageIOThumbnail.load(contentsOf: url, maxPixelSize: 100))
        let cg = try #require(image.cgImage)
        #expect(image.imageOrientation == .up)
        #expect(max(cg.width, cg.height) <= 100)
        #expect(cg.width > cg.height)
    }

    @Test func coveringLoadStillCoversTheTarget() throws {
        let url = try Self.writeJPEG(width: 400, height: 200, exifOrientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = CGSize(width: 80, height: 80)
        let cg = try #require(ImageIOThumbnail.load(contentsOf: url, coveringPixelSize: target)?.cgImage)
        #expect(cg.width >= 80 && cg.height >= 80)
        #expect(max(cg.width, cg.height) < 400)
    }

    private actor Counter {
        var current = 0
        var peak = 0
        var ran = 0
        func enter() { current += 1; ran += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    @Test func gateNeverRunsMoreThanTwoAtOnce() async {
        let gate = AsyncGate(limit: 2)
        let counter = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    _ = await gate.run {
                        await counter.enter()
                        try? await Task.sleep(for: .milliseconds(30))
                        await counter.leave()
                    }
                }
            }
        }
        #expect(await counter.peak == 2)
        #expect(await counter.ran == 12)
    }

    @Test func cancelledWaiterDoesNotRender() async {
        let gate = AsyncGate(limit: 1)
        let counter = Counter()
        let holder = Task {
            await gate.run { try? await Task.sleep(for: .milliseconds(300)) }
        }
        try? await Task.sleep(for: .milliseconds(50))
        let waiter = Task<Bool, Never> { await gate.run { await counter.enter() } != nil }
        try? await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        let result = await waiter.value
        _ = await holder.value
        #expect(!result)
        #expect(await counter.ran == 0)
    }
}
