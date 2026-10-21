import Foundation
import Testing
import UIKit
@testable import frmr

// v4 F1 acceptance: render time per strip, cold and warm. It asserts nothing
// about speed (simulator timings say little about a phone); it prints numbers
// for the implementation-status table. Run it on its own for a clean cold
// number, since other suites warm the shared CIContext:
//   -only-testing:frmrTests/StripRenderTimingTests
@Suite(.serialized)
struct StripRenderTimingTests {

    // A 12 MP capture as the phone stores it: landscape sensor pixels plus an
    // orientation tag. A gradient with a few blocks keeps it from being a
    // trivially uniform image.
    private static func syntheticCapture() -> UIImage? {
        let size = CGSize(width: 4032, height: 3024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(red: 0.9, green: 0.6, blue: 0.3, alpha: 1).cgColor,
                          UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(
                    gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: []
                )
            }
            for index in 0..<12 {
                UIColor(white: CGFloat(index) / 12, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat(index) * 320, y: 1200, width: 300, height: 600))
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .right)
    }

    @Test func measureStripRenderTime() throws {
        let photo = try #require(Self.syntheticCapture())
        let cells = (0..<Constants.entriesPerStrip).map { StripGenerator.Cell(image: photo, caption: "frame \($0)") }
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        var lines: [String] = []

        // The first stock's cold run is the process-cold number (context and
        // kernels); later stocks' first runs include only their cube build.
        // Mono cubes are the expensive build (every lattice point evaluated).
        let allOn = StripCustomization.FilmEffects(halation: true, bloom: true, lightLeak: true)
        let allOff = StripCustomization.FilmEffects(halation: false, bloom: false, lightLeak: false)
        let runs: [(StripCustomization.FilmStock, StripCustomization.FilmEffects, String)] = [
            (.portrait400, allOff, "effects off"),
            (.portrait400, allOn, "all effects on"),
            (.mono400, allOn, "all effects on"),
        ]
        for (stock, effects, effectsLabel) in runs {
            var customization = StripCustomization()
            customization.filmStock = stock
            customization.effects = effects

            func timeOneStrip() -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = StripGenerator.render(strip: cells, customization: customization, date: date)
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            }

            let cold = timeOneStrip()
            let warmRuns = (0..<5).map { _ in timeOneStrip() }.sorted()
            let warmMedian = warmRuns[warmRuns.count / 2]
            lines.append("[F1 timing] simulator, \(stock.label), \(effectsLabel), 4×4032×3024 strip: cold \(Int(cold)) ms, warm median \(Int(warmMedian)) ms, warm runs \(warmRuns.map { Int($0) })")
            #expect(cold > 0)
        }
        let report = lines.joined(separator: "\n")
        print(report)
        // The simulator shares the host file system, so the number is
        // readable after the run without digging through the result bundle
        try? (report + "\n").write(toFile: "/tmp/frmr-f1-timing.txt", atomically: true, encoding: .utf8)
    }
}
