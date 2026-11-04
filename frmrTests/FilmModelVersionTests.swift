import Foundation
import SwiftData
import Testing
import UIKit
@testable import frmr

// F-122-B: film model versioning. Version 2 is a copy of version 1 for now,
// so these tests check that the version is carried and looked up, not that
// the two sets differ.

private typealias Film = Constants.ImageProcessing.Film

struct FilmModelVersionCodableTests {

    @Test func aLookWithoutTheKeyDecodesAsVersionOne() throws {
        let json = Data(#"{"stock":"portrait400","blackAndWhite":false}"#.utf8)
        let look = try JSONDecoder().decode(FilmLook.self, from: json)
        #expect(look.modelVersion == 1)
    }

    @Test func newLooksAreCurrentAndRoundTrip() throws {
        #expect(FilmLook.stockDefaults(for: .cine500T).modelVersion == Film.currentModelVersion)
        #expect(FilmLook.original.modelVersion == Film.currentModelVersion)
        let v2 = FilmLook.stockDefaults(for: .mono400)
        #expect(try JSONDecoder().decode(FilmLook.self, from: JSONEncoder().encode(v2)).modelVersion == 2)
        let v1 = v2.with(modelVersion: 1)
        let decoded = try JSONDecoder().decode(FilmLook.self, from: JSONEncoder().encode(v1))
        #expect(decoded == v1 && decoded.modelVersion == 1)
    }

    @Test func stockDefaultsAreComparedAtTheLooksOwnVersion() {
        let v1 = FilmLook(stock: .portrait400, modelVersion: 1)
        #expect(v1.isStockDefault)
        var edited = v1
        edited.strengths.grain = 0.2
        #expect(!edited.isStockDefault)
    }

    @Test func aLookCarriesItsVersionIntoTheCustomization() {
        #expect(FilmLook(stock: .slide100, modelVersion: 1).customization.modelVersion == 1)
        #expect(FilmLook.stockDefaults(for: .slide100).customization.modelVersion == Film.currentModelVersion)
    }
}

struct FilmModelParametersTests {

    @Test func versionOneIsTheOriginalSet() throws {
        let v1 = FilmModelParameters.forVersion(1)
        #expect(v1.version == 1)
        #expect(v1.shadowToeExponent == Film.shadowToeExponent)
        #expect(v1.negative(for: .daylight200) == Film.Negative.daylight200)
        #expect(v1.negative(for: .none) == nil)
        #expect(v1.print(for: .matte) == Film.Print.matte)
        #expect(FilmModelParameters.forVersion(2).version == 2)
        #expect(FilmModelParameters.current.version == Film.currentModelVersion)
        #expect(StripCustomization.FilmStock.mono3200.negative(version: 1) == Film.Negative.mono3200)
        #expect(StripCustomization.PrintStock.cinema.profile(version: 1) == Film.Print.cinema)
    }

    @Test func theCubeCacheKeysOnTheVersion() {
        let negative = Film.Negative.daylight200, print = Film.Print.lab
        func key(_ parameters: FilmModelParameters) -> FilmLUT.Key {
            FilmLUT.Key(
                negative: negative, print: print, monochrome: false, exposureGain: 1,
                modelVersion: parameters.version, toeExponent: parameters.shadowToeExponent, dimension: 4
            )
        }
        #expect(key(.v1) != key(.v2))
        #expect(key(.v1) == key(.forVersion(1)))
    }

    @Test func versionOneRendersLikeTheOriginalSet() {
        let negative = Film.Negative.portrait400, print = Film.Print.lab
        let cube1 = FilmLUT.cube(negative: negative, print: print, monochrome: false, parameters: .v1, dimension: 5)
        let legacy = FilmLUT.cube(negative: negative, print: print, monochrome: false, dimension: 5)
        #expect(cube1 == legacy)
    }
}

@MainActor
struct FilmModelVersionFlowTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 48, height: 36), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 36))
        }
    }

    @Test func theEditorUpgradesAV1PhotoAndDiscardKeepsItV1() throws {
        let context = try makeContext()
        let v1 = FilmLook(stock: .portrait400, modelVersion: 1)
        let row = try RollViewModel.insert(original: image(), look: v1, capturedAt: .now, context: context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: row.photoPath)) }

        let edit = try #require(PhotoEditViewModel(editing: row))
        #expect(edit.look.modelVersion == Film.currentModelVersion)
        #expect(!edit.isModified, "the upgrade is not a user edit")
        edit.discard()
        #expect(row.look.modelVersion == 1, "discard leaves the stored look at v1")
    }

    @Test func saveStoresTheUpgradedVersion() async throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(
            original: image(), look: FilmLook(stock: .portrait400, modelVersion: 1), capturedAt: .now, context: context
        )
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: row.photoPath)) }
        let edit = try #require(PhotoEditViewModel(editing: row))
        edit.selectStock(.mono400)
        #expect(await edit.saveToRoll(context: context))
        #expect(row.look.modelVersion == Film.currentModelVersion)
    }

    @Test func aStripAsksForEachPhotosOwnVersion() {
        let strip = StripCustomization()
        let old = FilmLook(stock: .portrait400, modelVersion: 1)
        let new = FilmLook(stock: .portrait400, modelVersion: 2)
        #expect(strip.effective(forFrameStock: .portrait400, look: old).modelVersion == 1)
        #expect(strip.effective(forFrameStock: .portrait400, look: new).modelVersion == 2)

        var override = StripCustomization()
        override.filmStock = .cine500T
        #expect(override.effective(forFrameStock: .portrait400, look: old).modelVersion == 1)
        #expect(override.effective(forFrameStock: .portrait400, look: new).modelVersion == 2)
    }

    @Test func entriesWithoutStoredLooksReadAsVersionOne() {
        let legacy = DiaryEntry(photoPath: "p", prompt: "", response: "", filmStock: .mono400)
        #expect(legacy.look.modelVersion == 1)
    }
}
