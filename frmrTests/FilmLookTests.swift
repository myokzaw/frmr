import CoreImage
import Foundation
import Testing
import UIKit
@testable import frmr

// v5 F5: FilmLook, its migrations and the effect-strength pipeline.
// Strength 0 must be pixel-identical to the effect being off, strength 1 the
// v4 strength, and the new vignette must default to doing nothing.

// MARK: - Model and migration

struct FilmLookModelTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func defaultsMatchTheV4Look() {
        let look = FilmLook.stockDefaults(for: .portrait400)
        #expect(look.strengths == FilmLook.Strengths(halation: 1, haze: 0, lightLeak: 0, grain: 1, vignette: 0))
        #expect(look.printStock == nil && !look.blackAndWhite)
        #expect(look.isStockDefault)
        #expect(FilmLook.original.stock == .none && !FilmLook.original.altersPhoto)
        #expect(FilmLook(stock: .none, blackAndWhite: true).altersPhoto)
    }

    @Test func aV4ToggleStoredAsBoolMigratesToTheStockStrengthOrZero() throws {
        // v4 FilmEffects JSON: on → the v4 strength (1), off → 0, bloom is haze
        let strengths = try decode(FilmLook.Strengths.self, #"{"halation":false,"bloom":true,"lightLeak":true}"#)
        #expect(strengths.halation == 0)
        #expect(strengths.haze == 1)
        #expect(strengths.lightLeak == 1)
        #expect(strengths.grain == 1, "keys the old shape never had take the default")
        #expect(strengths.vignette == 0)
    }

    @Test func numbersDecodeAndClampToTheSliderRange() throws {
        let strengths = try decode(FilmLook.Strengths.self, #"{"halation":0.4,"haze":9,"lightLeak":-3,"grain":1.25,"vignette":0.5}"#)
        #expect(strengths.halation == 0.4)
        #expect(strengths.haze == Constants.ImageProcessing.Film.Strength.sliderMaximum)
        #expect(strengths.lightLeak == 0)
        #expect(strengths.grain == 1.25)
        #expect(strengths.vignette == 0.5)
    }

    @Test func hazeWinsOverTheOldBloomKeyAndNeitherIsWritten() throws {
        let both = try decode(FilmLook.Strengths.self, #"{"haze":0.3,"bloom":1}"#)
        #expect(both.haze == 0.3)
        let encoded = try JSONEncoder().encode(FilmLook.Strengths.stockDefaults)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("bloom"))
        #expect(text.contains("haze"))
    }

    @Test func aLookRoundTripsThroughJSON() throws {
        let look = FilmLook(
            stock: .cine500T, printStock: .matte, blackAndWhite: true,
            strengths: .init(halation: 0.2, haze: 0.9, lightLeak: 1.5, grain: 0.1, vignette: 0.7)
        )
        let data = try #require(FilmLook.encoded(look))
        #expect(FilmLook.decoded(from: data) == look)
        #expect(try JSONDecoder().decode(FilmLook.self, from: data) == look)
    }

    @Test func storedLooksWithOldShapesStillDecode() throws {
        // A v2 ISO stock migrates, an unknown print falls back to the
        // stock's own, and the v4 `effects` key is read as strengths
        let look = try decode(
            FilmLook.self,
            #"{"stock":"iso400","printStock":"bogus","effects":{"halation":true,"bloom":true,"lightLeak":false}}"#
        )
        #expect(look.stock == .portrait400)
        #expect(look.printStock == nil)
        #expect(look.strengths.halation == 1 && look.strengths.haze == 1 && look.strengths.lightLeak == 0)
        #expect(FilmLook.decoded(from: Data("not json".utf8)) == .original, "a damaged row still shows its photo")
    }

    @Test func switchingStockKeepsStrengthsAndDropsAnUnusablePrint() {
        var look = FilmLook(stock: .daylight200, printStock: .matte)
        look.strengths.grain = 0.4
        let slide = look.with(stock: .slide100)
        #expect(slide.printStock == nil, "slide film has no matte print")
        #expect(slide.strengths.grain == 0.4)
        #expect(look.with(stock: .cine500T).printStock == .matte)
    }

    @Test func theLookBridgesToTheStripPipeline() {
        let look = FilmLook(
            stock: .slide100, printStock: .matte, blackAndWhite: true,
            strengths: .init(halation: 0, haze: 1, lightLeak: 0, grain: 1, vignette: 0.5)
        )
        let customization = look.customization
        #expect(customization.filmStock == .slide100)
        #expect(customization.resolvedPrint == .projection, "slide film is projection-only")
        #expect(customization.blackAndWhite)
        #expect(customization.strengths == look.strengths)
    }

    @Test func clampedStrengthHandlesNaNAndRange() {
        #expect(FilmLook.clampedStrength(.nan) == 0)
        #expect(FilmLook.clampedStrength(-1) == 0)
        #expect(FilmLook.clampedStrength(0.6) == 0.6)
        #expect(FilmLook.clampedStrength(3) == Constants.ImageProcessing.Film.Strength.sliderMaximum)
    }

    @Test func theLegacyToggleFacadeMeansStrengthAboveZero() {
        var customization = StripCustomization()
        #expect(customization.effects.halation && !customization.effects.bloom && !customization.effects.lightLeak)

        customization.effects = .init(halation: false, bloom: true, lightLeak: true)
        #expect(customization.strengths.halation == 0)
        #expect(customization.strengths.haze == 1)
        #expect(customization.strengths.lightLeak == 1)

        // Switching an already-on effect on again keeps the user's strength
        customization.strengths.haze = 0.4
        customization.effects.bloom = true
        #expect(customization.strengths.haze == 0.4)
        customization.effects.bloom = false
        #expect(customization.strengths.haze == 0)
        // Grain and vignette have no toggle and are never touched by it
        #expect(customization.strengths.grain == 1 && customization.strengths.vignette == 0)
    }

    @Test func storedStripDefaultsMigrateFromBoolsAndTheBloomKey() throws {
        let suite = "frmr.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        typealias K = Constants.DefaultsKeys

        #expect(StripViewModel.storedStrengths(in: defaults) == .stockDefaults, "nothing stored = the defaults")

        // v4 wrote Bools under these keys, bloom under its own
        defaults.set(false, forKey: K.stripHalation)
        defaults.set(true, forKey: K.stripBloom)
        defaults.set(true, forKey: K.stripLightLeak)
        var migrated = StripViewModel.storedStrengths(in: defaults)
        #expect(migrated.halation == 0 && migrated.haze == 1 && migrated.lightLeak == 1)

        // The new haze key wins once it exists; strengths store as numbers
        defaults.set(0.35, forKey: K.stripHaze)
        defaults.set(2.5, forKey: K.stripGrain)
        migrated = StripViewModel.storedStrengths(in: defaults)
        #expect(migrated.haze == 0.35)
        #expect(migrated.grain == Constants.ImageProcessing.Film.Strength.sliderMaximum, "clamped to the slider range")

        var customization = StripCustomization()
        customization.strengths = .init(halation: 0.5, haze: 0.25, lightLeak: 0.75, grain: 0.1, vignette: 0.9)
        StripViewModel.storeDefaults(customization, in: defaults)
        #expect(StripViewModel.loadDefaults(from: defaults).strengths == customization.strengths)
    }

    @Test func entriesRoundTripAWholeLookAndOldRowsKeepTheirStockDefaults() {
        let old = DiaryEntry(photoPath: "p", prompt: "", response: "", filmStock: .mono400)
        #expect(old.lookData == nil)
        #expect(old.look == .stockDefaults(for: .mono400))

        var look = FilmLook.stockDefaults(for: .portrait400)
        look.strengths.vignette = 0.6
        let edited = DiaryEntry(photoPath: "p", prompt: "", response: "", look: look)
        #expect(edited.filmStock == .portrait400)
        #expect(edited.look == look)

        let untouched = DiaryEntry(photoPath: "p", prompt: "", response: "", look: .stockDefaults(for: .slide100))
        #expect(untouched.lookData == nil, "stock defaults are not stored")
    }
}

// MARK: - Pipeline: strength 0 is off, 1 is v4

struct EffectStrengthPipelineTests {

    private let width: CGFloat = 400

    @Test func strengthOneIsTheV4Effect() throws {
        let image = ciFlat(0.6)
        #expect(
            Raster(ImageProcessor.applyBloom(to: image, outputWidth: width, strength: 1))
                == Raster(ImageProcessor.applyBloom(to: image, outputWidth: width))
        )
        #expect(
            Raster(ImageProcessor.applyLightLeak(to: image, seed: 9, strength: 1))
                == Raster(ImageProcessor.applyLightLeak(to: image, seed: 9))
        )
    }

    @Test func aWholeRenderAtV4TogglesEqualsTheStrengthOneRender() throws {
        let source = flatImage(0.4)
        var legacy = StripCustomization.stockDefaults(for: .portrait400)
        legacy.effects = .init(halation: true, bloom: true, lightLeak: true)
        var modern = StripCustomization.stockDefaults(for: .portrait400)
        modern.strengths = .init(halation: 1, haze: 1, lightLeak: 1, grain: 1, vignette: 0)

        let a = try #require(Raster(ImageProcessor.applyStripLook(to: source, customization: legacy, outputWidth: 120, seed: 3)))
        let b = try #require(Raster(ImageProcessor.applyStripLook(to: source, customization: modern, outputWidth: 120, seed: 3)))
        #expect(a == b)
    }

    @Test func grainStrengthMultipliesTheStocksGrain() throws {
        let source = flatImage(0.4, size: CGSize(width: 240, height: 192))
        func variance(_ grain: Double) throws -> Double {
            var customization = StripCustomization.stockDefaults(for: .mono3200)
            customization.strengths = .allOff
            customization.strengths.grain = grain
            let image = try ImageProcessor.renderFullLook(
                of: source, look: FilmLook(stock: .mono3200, strengths: customization.strengths), seed: 4
            )
            return try #require(Raster(image)).variance
        }
        let zero = try variance(0), half = try variance(0.5), full = try variance(1), boosted = try variance(1.5)
        // Grain 0 leaves a flat photo flat (the film cube alone adds no noise)
        #expect(zero < 0.5, "variance at grain 0: \(zero)")
        #expect(full > zero + 1, "grain 1 adds visible grain: \(zero) -> \(full)")
        #expect(zero < half && half < full && full < boosted, "variance \(zero) < \(half) < \(full) < \(boosted)")
    }

    @Test func hazeAndLightLeakScaleWithStrength() throws {
        let image = ciFlat(0.3, size: CGSize(width: 96, height: 96))
        func mean(_ result: CIImage) throws -> Double { try #require(Raster(result)).mean }
        let base = try mean(image)
        let leakHalf = try mean(ImageProcessor.applyLightLeak(to: image, seed: 2, strength: 0.5))
        let leakFull = try mean(ImageProcessor.applyLightLeak(to: image, seed: 2, strength: 1))
        let leakMax = try mean(ImageProcessor.applyLightLeak(to: image, seed: 2, strength: 1.5))
        #expect(base < leakHalf && leakHalf < leakFull && leakFull < leakMax)

        // Haze needs something to spread: a bright dot on black
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 30, y: 30, width: 4, height: 4))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        let hazeHalf = try mean(ImageProcessor.applyBloom(to: dot, outputWidth: width, strength: 0.5))
        let hazeFull = try mean(ImageProcessor.applyBloom(to: dot, outputWidth: width, strength: 1))
        #expect(try mean(dot) < hazeHalf && hazeHalf < hazeFull)
    }

    @Test func halationScalesWithStrength() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 64)
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 30, y: 30, width: 4, height: 4))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        func mean(_ strength: Double) throws -> Double {
            try #require(Raster(ImageProcessor.applyHalation(to: dot, strength: strength, outputWidth: width))).mean
        }
        #expect(try mean(0) < mean(0.5))
        #expect(try mean(0.5) < mean(1))
    }

    @Test func aLeakKeepsItsPlaceWhateverTheStrength() throws {
        // Positions come from the seed alone: a stronger leak is the same
        // glow brighter, so where it brightens the image must not move
        let image = ciFlat(0, size: CGSize(width: 96, height: 96))
        let half = try #require(Raster(ImageProcessor.applyLightLeak(to: image, seed: 12, strength: 0.5)))
        let full = try #require(Raster(ImageProcessor.applyLightLeak(to: image, seed: 12, strength: 1)))
        for y in stride(from: 0, to: 96, by: 8) {
            for x in stride(from: 0, to: 96, by: 8) {
                #expect((half.luma(x, y) > 0) == (full.luma(x, y) > 0) || full.luma(x, y) < 6)
            }
        }
    }
}

// MARK: - Vignette (v5 F5, overturns OPEN v4-4)

struct VignetteTests {

    @Test func theCornersDarkenAndTheCentreDoesNot() throws {
        let image = ciFlat(0.7, size: CGSize(width: 100, height: 100))
        let before = try #require(Raster(image))
        let after = try #require(Raster(ImageProcessor.applyVignette(to: image, strength: 1)))
        #expect(after.luma(50, 50) == before.luma(50, 50), "the centre is inside the inner radius")
        #expect(after.luma(1, 1) < before.luma(1, 1) - 20, "corner \(after.luma(1, 1)) vs \(before.luma(1, 1))")
        #expect(after.luma(50, 1) <= before.luma(50, 1))
    }

    @Test func aStrongerVignetteDarkensMoreAndNeverBrightens() throws {
        let image = ciFlat(0.7, size: CGSize(width: 100, height: 100))
        let corners = try [0.25, 0.5, 1.0, 1.5].map { strength in
            try #require(Raster(ImageProcessor.applyVignette(to: image, strength: strength))).luma(1, 1)
        }
        #expect(corners == corners.sorted(by: >), "corners get darker with strength: \(corners)")
        let source = try #require(Raster(image))
        let strongest = try #require(Raster(ImageProcessor.applyVignette(to: image, strength: 1.5)))
        for y in stride(from: 0, to: 100, by: 11) {
            for x in stride(from: 0, to: 100, by: 11) {
                #expect(strongest.luma(x, y) <= source.luma(x, y) + 0.5)
            }
        }
    }

    @Test func theVignetteReachesTheFullRenderWithoutMovingTheMiddle() throws {
        let source = flatImage(0.5, size: CGSize(width: 160, height: 120))
        var look = FilmLook.stockDefaults(for: .slide100)
        look.strengths.grain = 0
        let plain = try #require(Raster(try ImageProcessor.renderFullLook(of: source, look: look, seed: 1)))
        look.strengths.vignette = 1
        let vignetted = try #require(Raster(try ImageProcessor.renderFullLook(of: source, look: look, seed: 1)))
        #expect(vignetted.luma(80, 60) == plain.luma(80, 60))
        #expect(vignetted.luma(2, 2) < plain.luma(2, 2))
    }

    @Test func aStripFrameCanCarryTheVignette() throws {
        var customization = StripCustomization.stockDefaults(for: .portrait400)
        customization.strengths.vignette = 1
        let source = flatImage(0.6, size: CGSize(width: 160, height: 200))
        let plain = try #require(Raster(ImageProcessor.applyStripLook(
            to: source, customization: .stockDefaults(for: .portrait400), outputWidth: 80, seed: 2
        )))
        let vignetted = try #require(Raster(ImageProcessor.applyStripLook(to: source, customization: customization, outputWidth: 80, seed: 2)))
        #expect(vignetted.mean < plain.mean)
    }
}

// MARK: - Roll frames keep their own look in a strip (v5 F6)

@MainActor
struct StripRollLookTests {

    @Test func asShotRendersARollFramesOwnLookWithTheStripBackground() {
        var strip = StripCustomization()
        strip.background = .black
        strip.filmStock = nil
        strip.strengths = .allOff
        let look = FilmLook(
            stock: .cine500T, printStock: .matte, blackAndWhite: true,
            strengths: .init(halation: 0.2, haze: 0, lightLeak: 0.5, grain: 1, vignette: 0.3)
        )
        let frame = strip.effective(forFrameStock: .none, look: look)
        #expect(frame.filmStock == .cine500T && frame.printStock == .matte && frame.blackAndWhite)
        #expect(frame.strengths == look.strengths, "not the strip's own strengths")
        #expect(frame.background == .black)
    }

    @Test func anOverrideStockWinsOverTheRollLook() {
        var strip = StripCustomization()
        strip.filmStock = .slide100
        let frame = strip.effective(forFrameStock: .cine500T, look: .stockDefaults(for: .cine500T))
        #expect(frame.filmStock == .slide100)
    }

    @Test func aFrameWithoutALookBehavesAsBefore() {
        let strip = StripCustomization()
        #expect(strip.effective(forFrameStock: .mono400, look: nil) == strip.effective(forFrameStock: .mono400))
    }

    @Test func itemsAndCellsTakeTheirStockFromTheLook() {
        let look = FilmLook.stockDefaults(for: .mono3200)
        #expect(StripItem(image: nil, caption: "", entryID: nil, look: look).filmStock == .mono3200)
        #expect(StripGenerator.Cell(image: nil, caption: "", look: look).filmStock == .mono3200)
    }
}
