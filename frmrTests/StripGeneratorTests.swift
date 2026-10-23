import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// StripGenerator: chunking, layout, the plain booth strip, and superseded renders.

struct StripGeneratorTests {

    private func makeCells(_ count: Int) -> [StripGenerator.Cell] {
        (0..<count).map { StripGenerator.Cell(image: nil, caption: "caption \($0)") }
    }

    @Test func fourEntriesMakeOneFullStrip() {
        let strips = StripGenerator.chunked(makeCells(4), paddingWith: .empty)

        #expect(strips.count == 1)
        #expect(strips[0].count == Constants.entriesPerStrip)
        #expect(strips[0].allSatisfy { !$0.caption.isEmpty })
    }

    @Test func fiveEntriesMakeTwoStripsSecondPaddedWithThreeEmptyCells() {
        let strips = StripGenerator.chunked(makeCells(5), paddingWith: .empty)

        #expect(strips.count == 2)
        #expect(strips[1].count == Constants.entriesPerStrip)
        #expect(strips[1][0].caption == "caption 4")

        let emptyCells = strips[1].filter { $0.caption.isEmpty && $0.image == nil }
        #expect(emptyCells.count == 3)
    }

    @Test func zeroEntriesMakeNoStrips() {
        let strips = StripGenerator.chunked(makeCells(0), paddingWith: .empty)

        #expect(strips.isEmpty)
    }

    @Test func renderedStripHasSpecWidth() {
        let image = StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: .now
        )

        #expect(image.size.width == Constants.Strip.width)
        #expect(image.size.height > 0)
        #expect(image.scale == Constants.Strip.renderScale)
    }

    // MARK: v4 F8 / F15 — plain booth strip

    private enum PlainGeometry {
        static let layout = StripGenerator.Layout()
        static let scale = Constants.Strip.renderScale

        /// Photo slots in pixels, grown by a pixel for edge antialiasing.
        static var photoRects: [CGRect] {
            (0..<Constants.entriesPerStrip).map { index in
                let rect = layout.photoRect(at: index)
                return CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
                    .insetBy(dx: -1, dy: -1)
            }
        }

        /// The bottom date stamp's full-width band, in pixels.
        static var dateBand: Range<Int> {
            let date = layout.dateRect
            return Int(floor(date.minY * scale)) - 1 ..< Int(ceil(date.maxY * scale)) + 1
        }
    }

    // Empty captions, so the caption bands must be plain paper too: that is
    // where v2's frame numbers were printed. The paper carries a faint
    // texture (v4 F15), so "plain" means within its amplitude of the tone.
    @Test(arguments: [StripCustomization.StripBackground.white, .black])
    func plainStripHasNoMarksOutsidePhotosAndText(background: StripCustomization.StripBackground) throws {
        var customization = StripCustomization()
        customization.background = background
        let strip = StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: customization,
            date: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let buffer = try #require(PixelBuffer(strip))
        let paper = background.paperRGB
        let tolerance = Constants.Strip.paperTextureAmplitude * 255 + 1.5

        let excluded = PlainGeometry.photoRects
        let dateBand = PlainGeometry.dateBand
        var marks = 0
        for y in 0..<buffer.height where !dateBand.contains(y) {
            for x in 0..<buffer.width {
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                guard !excluded.contains(where: { $0.contains(point) }) else { continue }
                let pixel = buffer.rgb(x: x, y: y)
                if abs(pixel.r - paper.r * 255) > tolerance || abs(pixel.g - paper.g * 255) > tolerance
                    || abs(pixel.b - paper.b * 255) > tolerance {
                    marks += 1
                }
            }
        }
        #expect(marks == 0, "\(marks) pixels differ from the paper outside photos and text")
    }

    @Test func theDateStampIsStillPrinted() throws {
        let buffer = try #require(PixelBuffer(StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: Date(timeIntervalSince1970: 1_790_000_000)
        )))
        let inked = PlainGeometry.dateBand.contains { y in
            (0..<buffer.width).contains { x in buffer.rgb(x: x, y: y).r < 128 }
        }
        #expect(inked, "no date stamp in the bottom band")
    }
}

// MARK: - v4 F15: booth strip

struct BoothStripTests {

    private let layout = StripGenerator.Layout()
    private typealias S = Constants.Strip

    @Test func framesArePortraitFourByFive() {
        for index in 0..<Constants.entriesPerStrip {
            let frame = layout.photoRect(at: index)
            #expect(abs(frame.width / frame.height - 4.0 / 5.0) < 1e-9)
        }
        #expect(S.cellAspectRatio == 0.8)
    }

    @Test func borderAndGapsMatchTheirConstants() {
        let first = layout.photoRect(at: 0)
        #expect(first.minX == S.border && first.minY == S.border)
        #expect(S.width - first.maxX == S.border, "the border is even left and right")
        for index in 0..<Constants.entriesPerStrip {
            let caption = layout.captionRect(at: index)
            #expect(caption.minY - layout.photoRect(at: index).maxY == S.captionSpacing, "caption sits under its frame")
            if index + 1 < Constants.entriesPerStrip {
                #expect(abs(layout.photoRect(at: index + 1).minY - caption.maxY - S.frameGap) < 1e-9)
            }
        }
        let lastCaption = layout.captionRect(at: Constants.entriesPerStrip - 1)
        #expect(abs(layout.dateRect.minY - lastCaption.maxY - S.frameGap) < 1e-9)
        #expect(abs(layout.totalSize.height - layout.dateRect.maxY - S.border) < 1e-9)
        #expect(S.border <= 8 && S.frameGap <= 6, "a booth strip's border and gaps are thin")
    }

    @Test func paperIsNeitherPureWhiteNorPureBlack() throws {
        for background in StripCustomization.StripBackground.allCases {
            var customization = StripCustomization()
            customization.background = background
            let buffer = try #require(PixelBuffer(StripGenerator.render(
                strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
                customization: customization, date: Date(timeIntervalSince1970: 1_790_000_000)
            )))
            let corner = buffer.rgb(x: 2, y: 2)
            if background == .white {
                #expect(corner.r < 252 && corner.b < 240 && corner.r > 225, "warm off-white, got \(corner)")
                #expect(corner.r > corner.b, "the white paper is warm")
            } else {
                #expect(corner.r > 10 && corner.r < 40, "near-black, got \(corner)")
            }
        }
    }
}

// MARK: - v4 F1: superseded renders

@MainActor
struct StripViewModelRenderTests {

    @Test func aSupersededRenderLeavesTheNewestInCharge() async {
        let photo = solidImage(UIColor(white: 0.5, alpha: 1), size: CGSize(width: 320, height: 240))
        let items = (0..<Constants.entriesPerStrip).map { _ in StripItem(image: photo, caption: "", entryID: nil) }
        let viewModel = StripViewModel(items: items, isPhotobooth: true)
        viewModel.customization.filmStock = .portrait400

        let first = Task { await viewModel.renderStrips() }
        viewModel.customization.blackAndWhite = true
        await viewModel.renderStrips()
        await first.value

        #expect(!viewModel.isRendering)
        #expect(viewModel.stripImages.count == 1)
    }
}
