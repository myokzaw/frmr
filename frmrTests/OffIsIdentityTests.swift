import CoreImage
import Foundation
import Testing
import UIKit
@testable import frmr

// Identity invariants (docs/film-simulation.md §8.5): "0 equals off" and
// "stock Off changes nothing". One parameterised test per way of getting to
// the identity, so a new effect or a new surface is one more argument, not
// one more near-duplicate test. See docs/testing.md.

// MARK: - Strength 0 is pixel-identical to the input

struct StrengthZeroIdentityTests {

    /// Every effect, applied at strength 0 (grain at intensity 0).
    enum Effect: CaseIterable, CustomTestStringConvertible {
        case halation, haze, lightLeak, vignette, grain

        var testDescription: String { String(describing: self) }

        func applyingZeroStrength(to image: CIImage) -> CIImage {
            switch self {
            case .halation: ImageProcessor.applyHalation(to: image, strength: 0, outputWidth: 400)
            case .haze: ImageProcessor.applyBloom(to: image, outputWidth: 400, strength: 0)
            case .lightLeak: ImageProcessor.applyLightLeak(to: image, seed: 5, strength: 0)
            case .vignette: ImageProcessor.applyVignette(to: image, strength: 0)
            case .grain: ImageProcessor.addGrain(to: image, intensity: 0, sizePixels: 2, monochrome: false, seed: 1)
            }
        }
    }

    /// A flat mid grey, and a bright dot on black (the case where halation
    /// and haze have highlights to act on, so "nothing happened" means something).
    enum Input: CaseIterable, CustomTestStringConvertible {
        case flatMidGrey, brightDotOnBlack

        var testDescription: String { String(describing: self) }

        var image: CIImage {
            let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
            switch self {
            case .flatMidGrey:
                return ciFlat(0.5, size: extent.size)
            case .brightDotOnBlack:
                return CIImage(color: .white).cropped(to: CGRect(x: 30, y: 30, width: 4, height: 4))
                    .composited(over: CIImage(color: .black).cropped(to: extent))
            }
        }
    }

    @Test(arguments: Effect.allCases, Input.allCases)
    func effectAtZeroStrengthIsPixelIdentical(effect: Effect, input: Input) throws {
        let image = input.image
        let before = try #require(Raster(image))
        #expect(Raster(effect.applyingZeroStrength(to: image)) == before)
    }

    /// The vignette defaults to 0, so a stock's full look is the same with
    /// the vignette explicitly zero (every stock, grain and leak seeded alike).
    @Test(arguments: StripCustomization.FilmStock.allCases.filter { $0 != .none })
    func vignetteZeroLeavesTheStockLookUnchanged(stock: StripCustomization.FilmStock) throws {
        let source = flatImage(0.5)
        let plain = try #require(Raster(try ImageProcessor.renderFullLook(of: source, stock: stock, seed: 6)))
        var look = FilmLook.stockDefaults(for: stock)
        look.strengths.vignette = 0
        let explicit = try #require(Raster(try ImageProcessor.renderFullLook(of: source, look: look, seed: 6)))
        #expect(plain == explicit, "\(stock.label)")
    }
}

// MARK: - Stock Off returns the original, not a copy

@MainActor
struct StockOffIdentityTests {

    /// Every surface that can show a photo in a stock. The strip look has its
    /// own, wider matrix (StripLookDeterminismRegressionTests.offFastPathReturnsTheOriginal:
    /// orientations × effects × prints).
    enum Surface: CaseIterable, CustomTestStringConvertible {
        case fullLook, filmLookCache, photoEdit

        var testDescription: String { String(describing: self) }
    }

    @Test(arguments: Surface.allCases)
    func stockOffReturnsTheOriginalInstanceWithoutRendering(surface: Surface) throws {
        switch surface {
        case .fullLook:
            // A tagged capture: the sensor pixels and the tag stay untouched
            let tagged = UIImage(cgImage: try #require(solidImage(.red).cgImage), scale: 1, orientation: .left)
            #expect(try ImageProcessor.renderFullLook(of: tagged, stock: .none, seed: 1) === tagged)

        case .filmLookCache:
            let photo = solidImage(.gray)
            let shown = FilmLookCache().image(id: UUID(), stock: .none, seed: 0, pixelSize: CGSize(width: 8, height: 8)) { photo }
            #expect(shown === photo)

        case .photoEdit:
            let preview = solidImage(.gray, size: CGSize(width: 96, height: 72))
            let edit = PhotoEditViewModel(preview: preview, stock: .none)
            #expect(edit.renderedPhoto === preview && edit.displayedPhoto === preview)
            #expect(!edit.isRendering)
            #expect(!edit.areEffectsAvailable && !edit.isPrintPickerVisible)
        }
    }
}
