import Foundation
import Testing
import UIKit
@testable import frmr

// Calibration tool for OPEN v4-5, not a regression test. It develops real RAW
// captures through the app's own pipeline and lays every stock side by side,
// so the curve numbers can be judged on real photos rather than synthetic
// patches. Photos are personal and stay out of the repo: point the test at a
// folder with environment variables and it writes one sheet per photo.
//
//   TEST_RUNNER_FRMR_FILM_SAMPLES_DIR=<folder of .dng/.DNG files>
//   TEST_RUNNER_FRMR_FILM_SAMPLES_OUT=<output folder>
//   xcodebuild … -only-testing:frmrTests/FilmStockSampleSheetTests test
//
// Without both variables the test is skipped.
//
// F-122-A also writes before/after sheets (film model 1 next to 2) per photo:
// <name>-before-after.jpg (every stock on its default print),
// <name>-prints-before-after.jpg (every print on Portrait 400), and one
// synthetic sheet, ramps-before-after.jpg (grey steps for every stock).
struct FilmStockSampleSheetTests {

    private static let samplesDir = ProcessInfo.processInfo.environment["FRMR_FILM_SAMPLES_DIR"]
    private static let outputDir = ProcessInfo.processInfo.environment["FRMR_FILM_SAMPLES_OUT"]

    // Sheet geometry: tiles sized for judging colour and grain on a laptop
    // screen, not for pixel peeping.
    private static let tileWidth: CGFloat = 640
    private static let labelHeight: CGFloat = 44
    private static let columns = 4
    private static let gutter: CGFloat = 12

    @Test(.enabled(if: samplesDir != nil && outputDir != nil, "Set FRMR_FILM_SAMPLES_DIR and FRMR_FILM_SAMPLES_OUT"))
    func renderEveryStockForEachSamplePhoto() throws {
        let input = URL(fileURLWithPath: try #require(Self.samplesDir))
        let output = URL(fileURLWithPath: try #require(Self.outputDir))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let photos = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "dng" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!photos.isEmpty, "No DNG files in \(input.path)")

        for photo in photos {
            let developed = try ImageProcessor.process(rawData: Data(contentsOf: photo))
            let tileHeight = Self.tileWidth * developed.size.height / max(developed.size.width, 1)
            let covering = CGSize(width: Self.tileWidth * 2, height: tileHeight * 2)

            var tiles: [(String, UIImage)] = []
            for stock in StripCustomization.FilmStock.allCases {
                // Fixed seed so reruns after a curve change compare like for like
                let rendered = try ImageProcessor.renderFullLook(
                    of: developed, stock: stock, seed: 1, coveringPixelSize: covering
                )
                tiles.append((stock.label, rendered))
            }

            let base = photo.deletingPathExtension().lastPathComponent
            let sheet = Self.sheet(tiles: tiles, tileHeight: tileHeight, title: base)
            let data = try #require(sheet.jpegData(compressionQuality: 0.9))
            try data.write(to: output.appendingPathComponent(base + "-stocks.jpg"))

            // v1 next to v2, every stock on its default print
            var stockPairs: [(String, UIImage)] = []
            for stock in StripCustomization.FilmStock.allCases where stock != .none {
                for version in [1, 2] {
                    let look = FilmLook(stock: stock, modelVersion: version)
                    stockPairs.append(("\(stock.label) · v\(version)", try ImageProcessor.renderFullLook(
                        of: developed, look: look, seed: 1, coveringPixelSize: covering)))
                }
            }
            try Self.write(
                Self.sheet(tiles: stockPairs, tileHeight: tileHeight, title: base + " · stocks, v1 | v2"),
                to: output.appendingPathComponent(base + "-before-after.jpg"))

            // v1 next to v2, every print on Portrait 400
            var printPairs: [(String, UIImage)] = []
            for printStock in StripCustomization.FilmStock.portrait400.availablePrints {
                for version in [1, 2] {
                    let look = FilmLook(stock: .portrait400, printStock: printStock, modelVersion: version)
                    printPairs.append(("Portrait 400 on \(printStock.rawValue) · v\(version)", try ImageProcessor.renderFullLook(
                        of: developed, look: look, seed: 1, coveringPixelSize: covering)))
                }
            }
            try Self.write(
                Self.sheet(tiles: printPairs, tileHeight: tileHeight, title: base + " · prints on Portrait 400, v1 | v2"),
                to: output.appendingPathComponent(base + "-prints-before-after.jpg"))
        }
    }

    // Synthetic ramps: 16 grey steps from 0 to 100% and 16 from 0 to 20%,
    // every stock on its default print, effects off so only tone shows.
    @Test(.enabled(if: samplesDir != nil && outputDir != nil, "Set FRMR_FILM_SAMPLES_DIR and FRMR_FILM_SAMPLES_OUT"))
    func renderGreyRampsForEveryStock() throws {
        let output = URL(fileURLWithPath: try #require(Self.outputDir))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let ramp = Self.rampImage()
        let covering = ramp.size
        var tiles: [(String, UIImage)] = []
        for stock in StripCustomization.FilmStock.allCases where stock != .none {
            for version in [1, 2] {
                let look = FilmLook(stock: stock, strengths: .allOff, modelVersion: version)
                tiles.append(("\(stock.label) · v\(version)", try ImageProcessor.renderFullLook(
                    of: ramp, look: look, seed: 1, coveringPixelSize: covering)))
            }
        }
        // Two columns: v1 left, v2 right. Each tile: top 0–100%, bottom 0–20%
        try Self.write(
            Self.sheet(tiles: tiles, tileHeight: ramp.size.height, title: "grey ramps, v1 | v2", columns: 2),
            to: output.appendingPathComponent("ramps-before-after.jpg"))
    }

    private static func rampImage() -> UIImage {
        let steps = 16
        let size = CGSize(width: tileWidth, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cell = size.width / CGFloat(steps)
            for row in 0..<2 {
                // Row 0: 0–100%; row 1: 0–20%
                let top: CGFloat = row == 0 ? 1 : 0.2
                for step in 0..<steps {
                    let level = top * CGFloat(step) / CGFloat(steps - 1)
                    UIColor(white: level, alpha: 1).setFill()
                    context.fill(CGRect(x: CGFloat(step) * cell, y: CGFloat(row) * size.height / 2, width: cell + 1, height: size.height / 2))
                }
            }
        }
    }

    private static func write(_ image: UIImage, to url: URL) throws {
        let data = try #require(image.jpegData(compressionQuality: 0.85))
        try data.write(to: url)
    }

    private static func sheet(tiles: [(String, UIImage)], tileHeight: CGFloat, title: String, columns: Int = FilmStockSampleSheetTests.columns) -> UIImage {
        let rows = Int((Double(tiles.count) / Double(columns)).rounded(.up))
        let cellHeight = tileHeight + labelHeight
        let size = CGSize(
            width: CGFloat(columns) * tileWidth + CGFloat(columns + 1) * gutter,
            height: labelHeight + CGFloat(rows) * cellHeight + CGFloat(rows + 1) * gutter
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.12, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            NSAttributedString(string: title, attributes: titleAttributes)
                .draw(at: CGPoint(x: gutter, y: gutter))

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white,
            ]
            for (index, tile) in tiles.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gutter + CGFloat(column) * (tileWidth + gutter)
                let y = labelHeight + gutter + CGFloat(row) * (cellHeight + gutter)
                // draw(in:) honours the orientation tag the pipeline preserves
                tile.1.draw(in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
                NSAttributedString(string: tile.0, attributes: labelAttributes)
                    .draw(at: CGPoint(x: x, y: y + tileHeight + 8))
            }
        }
    }
}
