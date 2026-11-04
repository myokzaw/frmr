import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import frmr

// F-122-E: import from the gallery. The batch state machine, the decode
// path and downscale, metadata removal, `RollPhoto.source`, and the session
// that drives the editor. Files go to Documents/Roll, so tests that write
// remove what they made.

private func solid(_ size: CGSize, white: CGFloat = 0.5) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

/// A JPEG that carries GPS, EXIF and TIFF details, like a phone photo.
private func geotaggedJPEG(size: CGSize = CGSize(width: 200, height: 100)) throws -> Data {
    let cgImage = try #require(solid(size).cgImage)
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W",
        ],
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:00:00",
            kCGImagePropertyExifLensModel: "Test Lens",
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCo", kCGImagePropertyTIFFModel: "T-1"],
    ]
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func removeFiles(_ photos: [RollPhoto]) {
    for photo in photos {
        try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: photo.photoPath))
    }
}

private struct Unreadable: Error {}

// MARK: - Batch state machine

struct ImportBatchTests {
    @Test func theCounterReadsPositionOfTotal() {
        var batch = ImportBatch(total: 5)
        #expect(batch.counterText == "1 of 5")
        batch.markSaved()
        #expect(batch.counterText == "2 of 5")
        batch.markSkipped()
        #expect(batch.counterText == "3 of 5" && batch.currentIndex == 2)
    }

    @Test func saveAndSkipAdvanceAndCount() {
        var batch = ImportBatch(total: 3)
        batch.markSaved()
        batch.markSkipped()
        #expect(batch.savedCount == 1 && batch.skippedCount == 1 && !batch.isFinished)
        batch.markSaved()
        #expect(batch.isFinished && batch.currentIndex == nil && batch.savedCount == 2)
        batch.markSaved()
        #expect(batch.savedCount == 2)
    }

    @Test func cancelStopsAndKeepsWhatWasSaved() {
        var batch = ImportBatch(total: 4)
        batch.markSaved()
        batch.markSaved()
        batch.cancel()
        #expect(batch.isFinished && batch.currentIndex == nil && batch.savedCount == 2)
        batch.markSaved()
        #expect(batch.savedCount == 2)
    }

    @Test func anUnreadablePickIsCountedAndTheBatchContinues() {
        var batch = ImportBatch(total: 3)
        batch.markFailed()
        #expect(batch.failedCount == 1 && batch.currentIndex == 1 && !batch.isFinished)
    }

    @Test func aRemainingPickExistsUntilTheLastOne() {
        var batch = ImportBatch(total: 2)
        #expect(batch.hasRemaining)
        batch.markSaved()
        #expect(!batch.hasRemaining)
    }

    @Test func theRestLookKeepsTheLookButNotTheCropOrTurns() {
        var look = FilmLook.stockDefaults(for: .portrait400)
        look.exposure = 1
        look.shadows = 20
        look.crop = CropRect(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), preset: .free, isLandscape: true)
        look.quarterTurns = 1
        let rest = ImportBatch.restLook(from: look)
        #expect(rest.crop == nil && rest.quarterTurns == 0)
        #expect(rest.stock == .portrait400 && rest.exposure == 1 && rest.shadows == 20)
        #expect(rest.modelVersion == look.modelVersion)
    }
}

// MARK: - Decode, downscale, metadata

@MainActor
struct GalleryImportDecodeTests {
    @Test func aRawRepresentationChoosesTheRawPath() throws {
        let dng = try #require(UTType("com.adobe.raw-image"))
        #expect(GalleryImportDecoder.path(forContentTypes: [.heic, dng]) == .raw)
        #expect(GalleryImportDecoder.path(forContentTypes: [.heic, .jpeg]) == .standard)
        #expect(GalleryImportDecoder.path(forTypeIdentifier: "com.adobe.raw-image") == .raw)
        #expect(GalleryImportDecoder.path(forTypeIdentifier: "public.jpeg") == .standard)
        #expect(GalleryImportDecoder.path(forTypeIdentifier: nil) == .standard)
    }

    @Test func aJPEGIsDetectedFromItsBytes() throws {
        #expect(GalleryImportDecoder.path(forData: try geotaggedJPEG()) == .standard)
        #expect(GalleryImportDecoder.path(forData: Data([1, 2, 3])) == .standard)
    }

    @Test func aLargePhotoComesDownToTheWorkingSize() throws {
        let wide = try geotaggedJPEG(size: CGSize(width: 6000, height: 1000))
        let decoded = try GalleryImportDecoder.decodeStandard(wide, maxLongSide: Constants.GalleryImport.maxLongSide)
        let cg = try #require(decoded.cgImage)
        #expect(max(cg.width, cg.height) == Constants.GalleryImport.maxLongSide)
        #expect(abs(Double(cg.width) / Double(cg.height) - 6) < 0.05)
    }

    @Test func aSmallPhotoIsNeverEnlarged() throws {
        let decoded = try GalleryImportDecoder.decodeStandard(try geotaggedJPEG(), maxLongSide: 4032)
        #expect(decoded.cgImage?.width == 200 && decoded.cgImage?.height == 100)
    }

    @Test func downscalingKeepsTheOrientationTag() throws {
        let cg = try #require(solid(CGSize(width: 800, height: 400)).cgImage)
        let tagged = UIImage(cgImage: cg, scale: 1, orientation: .right)
        let small = GalleryImportDecoder.downscaled(tagged, maxLongSide: 200)
        #expect(small.cgImage?.width == 200 && small.cgImage?.height == 100)
        #expect(small.imageOrientation == .right)
        #expect(GalleryImportDecoder.downscaled(tagged, maxLongSide: 4032).cgImage?.width == 800)
    }

    @Test func anUnreadableFileThrowsAnAppError() {
        #expect(throws: AppError.self) { try GalleryImportDecoder.decode(Data([0, 1, 2, 3])) }
    }

    @Test func theStoredCopyHasNoLocationOrOtherMetadata() throws {
        let source = try geotaggedJPEG()
        // The fixture really carries what we claim to strip
        let before = try #require(properties(of: source))
        #expect(before[kCGImagePropertyGPSDictionary] != nil)

        let decoded = try GalleryImportDecoder.decode(source)
        let context = try makeContext()
        let row = try RollViewModel.insert(
            original: decoded, look: .original, capturedAt: .now, context: context, source: .imported
        )
        defer { removeFiles([row]) }

        let written = try Data(contentsOf: FileManager.documentsURL(forRelativePath: row.photoPath))
        let after = try #require(properties(of: written))
        #expect(after[kCGImagePropertyGPSDictionary] == nil)
        let exif = after[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil && exif?[kCGImagePropertyExifLensModel] == nil)
        let tiff = after[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil && tiff?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func whatExportDrawsFromTheStoredCopyCarriesNoLocationEither() throws {
        let decoded = try GalleryImportDecoder.decode(try geotaggedJPEG())
        let heic = try ImageProcessor.fullResolutionHEIC(of: decoded, look: .original, seed: 1)
        let props = try #require(properties(of: heic))
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    private func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }
}

// MARK: - RollPhoto.source

@MainActor
struct RollPhotoSourceTests {
    @Test func aNewPhotoIsFromTheCameraUnlessSaidOtherwise() {
        #expect(RollPhoto(capturedAt: .now, photoPath: "Roll/x.jpg", look: .original).source == .camera)
        #expect(RollPhoto(capturedAt: .now, photoPath: "Roll/x.jpg", look: .original, source: .imported).source == .imported)
    }

    @Test func aRowWithNoOrUnknownSourceReadsAsCamera() {
        let row = RollPhoto(capturedAt: .now, photoPath: "Roll/x.jpg", look: .original)
        row.sourceRaw = "somethingElse"
        #expect(row.source == .camera)
        row.sourceRaw = ""
        #expect(row.source == .camera)
    }

    @Test func theSourceSurvivesAStoreRoundTrip() throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(
            original: solid(CGSize(width: 40, height: 30)), look: .original, capturedAt: .now,
            context: context, source: .imported
        )
        defer { removeFiles([row]) }
        let fetched = try #require(try context.fetch(FetchDescriptor<RollPhoto>()).first)
        #expect(fetched.source == .imported)
    }
}

// MARK: - Session

@MainActor
struct GalleryImportSessionTests {
    private func makeSession(
        count: Int, context: ModelContext, errors: ErrorState, failing: Set<Int> = [],
        loaded: LoadLog = LoadLog()
    ) -> GalleryImportSession {
        GalleryImportSession(count: count, context: context, errorState: errors, savePhotoData: { _ in }) { index in
            loaded.indices.append(index)
            if failing.contains(index) { throw Unreadable() }
            return solid(CGSize(width: 80, height: 60))
        }
    }

    /// Waits for the session to reach `condition` (its steps hop through Tasks).
    private func settle(_ session: GalleryImportSession, until condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func rows(_ context: ModelContext) throws -> [RollPhoto] {
        try context.fetch(FetchDescriptor<RollPhoto>())
    }

    @Test func eachImportStartsOffAtTheCurrentModelAndIsDatedNow() async throws {
        let context = try makeContext()
        let before = Date.now
        let session = makeSession(count: 2, context: context, errors: ErrorState())
        await session.start()
        let edit = try #require(session.current)
        #expect(edit.look.stock == .none)
        #expect(edit.look.modelVersion == Constants.ImageProcessing.Film.currentModelVersion)
        #expect(edit.importCounter == "1 of 2" && edit.isImportedPhoto && edit.canContinueToDiary)

        #expect(await edit.saveToRoll(context: context))
        let saved = try #require(try rows(context).first)
        defer { removeFiles([saved]) }
        #expect(saved.source == .imported)
        #expect(saved.capturedAt >= before && saved.capturedAt.timeIntervalSince(before) < 5)
        #expect(saved.look.modelVersion == Constants.ImageProcessing.Film.currentModelVersion && saved.look.stock == .none)
    }

    @Test func saveThenSkipWalksTheBatchAndOnlyTheSavedPhotoLands() async throws {
        let context = try makeContext()
        let session = makeSession(count: 2, context: context, errors: ErrorState())
        var closed = false
        session.onClose = { closed = true }
        await session.start()

        let first = try #require(session.current)
        await first.saveToRoll(context: context)
        await settle(session) { session.current?.id != first.id && session.current != nil }
        let second = try #require(session.current)
        #expect(second.importCounter == "2 of 2" && !second.importHasRemaining)

        second.skip()
        await settle(session) { closed }
        let stored = try rows(context)
        defer { removeFiles(stored) }
        #expect(stored.count == 1 && session.batch.savedCount == 1 && session.batch.skippedCount == 1)
        #expect(closed && session.current == nil)
    }

    @Test func cancelStopsTheBatchAndKeepsWhatWasSaved() async throws {
        let context = try makeContext()
        let loaded = LoadLog()
        let session = makeSession(count: 3, context: context, errors: ErrorState(), loaded: loaded)
        var closed = false
        session.onClose = { closed = true }
        await session.start()
        let first = try #require(session.current)
        await first.saveToRoll(context: context)
        await settle(session) { session.current?.id != first.id && session.current != nil }
        session.current?.discard()
        await settle(session) { closed }

        let stored = try rows(context)
        defer { removeFiles(stored) }
        #expect(stored.count == 1 && closed)
        #expect(loaded.indices == [0, 1])
    }

    @Test func applyToRestSavesTheLookWithoutTheCropOrTurnsThenFinishes() async throws {
        let context = try makeContext()
        let session = makeSession(count: 4, context: context, errors: ErrorState())
        var closed = false
        session.onClose = { closed = true }
        await session.start()
        let edit = try #require(session.current)
        edit.selectStock(.portrait400)
        edit.setExposure(1)
        edit.selectCropPreset(.oneByOne)
        edit.rotatePhoto()
        #expect(edit.look.crop != nil && edit.look.quarterTurns == 1)

        await edit.applyToRest(context: context)
        await settle(session) { closed }

        let stored = try rows(context)
        defer { removeFiles(stored) }
        #expect(stored.count == 4 && closed && session.batch.savedCount == 4)
        #expect(stored.allSatisfy { $0.source == .imported })
        let withCrop = stored.filter { $0.look.crop != nil }
        #expect(withCrop.count == 1)
        #expect(stored.filter { $0.look.quarterTurns == 1 }.count == 1)
        #expect(stored.allSatisfy { $0.look.stock == .portrait400 && $0.look.exposure == 1 })
        #expect(Set(stored.map(\.capturedAt)).count == 4)
    }

    @Test func applyToRestIsOfferedOnlyWhileAPickRemains() async throws {
        let context = try makeContext()
        let session = makeSession(count: 1, context: context, errors: ErrorState())
        await session.start()
        let edit = try #require(session.current)
        #expect(!edit.importHasRemaining)
        #expect(await edit.applyToRest(context: context) == false)
    }

    @Test func anUnreadablePickRaisesOneErrorAndTheBatchContinues() async throws {
        let context = try makeContext()
        let errors = ErrorState()
        let session = makeSession(count: 3, context: context, errors: errors, failing: [0])
        await session.start()

        // Pick 0 failed; the editor is on pick 1 ("2 of 3")
        let edit = try #require(session.current)
        #expect(edit.importCounter == "2 of 3")
        #expect(session.batch.failedCount == 1)
        guard case .importFailed? = errors.current else {
            Issue.record("expected importFailed, got \(String(describing: errors.current))")
            return
        }
    }

    @Test func applyToRestRaisesASingleAlertForSeveralUnreadablePicks() async throws {
        let context = try makeContext()
        let errors = ErrorState()
        let session = makeSession(count: 4, context: context, errors: errors, failing: [1, 2])
        var closed = false
        session.onClose = { closed = true }
        await session.start()
        let edit = try #require(session.current)
        await edit.applyToRest(context: context)
        await settle(session) { closed }

        let stored = try rows(context)
        defer { removeFiles(stored) }
        #expect(stored.count == 2 && session.batch.failedCount == 2)
        #expect(errors.current != nil)
    }

    @Test func aWholeBatchOfUnreadablePicksEndsWithoutAnEditor() async throws {
        let context = try makeContext()
        let session = makeSession(count: 2, context: context, errors: ErrorState(), failing: [0, 1])
        var closed = false
        session.onClose = { closed = true }
        await session.start()
        #expect(closed && session.current == nil && session.batch.failedCount == 2)
    }

    @Test func continueToDiaryCountsAsSavedAndHoldsTheNextPickUntilTheDiaryIsDone() async throws {
        let context = try makeContext()
        let session = makeSession(count: 2, context: context, errors: ErrorState())
        await session.start()
        let first = try #require(session.current)
        #expect(await first.continueToDiary(context: context))
        let stored = try rows(context)
        defer { removeFiles(stored) }
        #expect(session.diaryContinuation?.rollPhotoID == stored.first?.id && session.current == nil)

        session.diaryFinished()
        await settle(session) { session.current != nil }
        #expect(session.current?.importCounter == "2 of 2" && session.diaryContinuation == nil)
    }
}

/// Which picks the session asked for, in order.
private final class LoadLog: @unchecked Sendable {
    var indices: [Int] = []
}
