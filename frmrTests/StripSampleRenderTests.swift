import Foundation
import Testing
import UIKit
@testable import frmr

// Calibration tool for OPEN v4-16, not a regression test: develops four real
// RAW captures through the app's own pipeline and renders a booth strip on
// each paper, As shot with four different stocks. Photos are personal and
// stay out of the repo, so the test is skipped unless both variables are set:
//
//   TEST_RUNNER_FRMR_STRIP_SAMPLES_DIR=<folder of .dng/.DNG files>
//   TEST_RUNNER_FRMR_STRIP_SAMPLES_OUT=<output folder>
struct StripSampleRenderTests {

    private static let samplesDir = ProcessInfo.processInfo.environment["FRMR_STRIP_SAMPLES_DIR"]
    private static let outputDir = ProcessInfo.processInfo.environment["FRMR_STRIP_SAMPLES_OUT"]

    @Test(.enabled(if: samplesDir != nil && outputDir != nil, "Set FRMR_STRIP_SAMPLES_DIR and FRMR_STRIP_SAMPLES_OUT"))
    func renderABoothStripOnEachPaper() throws {
        let input = URL(fileURLWithPath: try #require(Self.samplesDir))
        let output = URL(fileURLWithPath: try #require(Self.outputDir))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let photos = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "dng" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(Constants.entriesPerStrip)
        let stocks: [StripCustomization.FilmStock] = [.daylight200, .cine500T, .slide100, .mono400]
        let captions = ["the edge of the cape", "late, by the window", "lake day, no wind", "the wheel at dusk"]
        let cells = try photos.enumerated().map { index, url in
            StripGenerator.Cell(
                image: try ImageProcessor.process(rawData: Data(contentsOf: url)),
                caption: captions[index % captions.count],
                filmStock: stocks[index % stocks.count]
            )
        }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        for background in StripCustomization.StripBackground.allCases {
            var customization = StripCustomization()
            customization.background = background
            let strip = StripGenerator.render(strip: cells, customization: customization, date: date)
            let data = try #require(strip.pngData())
            try data.write(to: output.appendingPathComponent("strip-v4-16-\(background.settingsName).png"))
        }
    }
}
