import CoreImage
import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
@testable import frmr

// v5 F6 (Roll) and F4 (PhotoEditViewModel). Files go to the host app's
// Documents/Roll folder, so every test that writes removes what it made.

private func photo(_ white: CGFloat = 0.5, size: CGSize = CGSize(width: 96, height: 72)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

private func pixelSize(of data: Data) -> CGSize? {
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return CGSize(width: width, height: height)
}

private func meanLuma(_ image: UIImage) -> Double {
    guard let cgImage = image.cgImage else { return 0 }
    let width = cgImage.width, height = cgImage.height
    var raw = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &raw, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sum = 0.0
    for index in stride(from: 0, to: raw.count, by: 4) {
        sum += (Double(raw[index]) + Double(raw[index + 1]) + Double(raw[index + 2])) / 3
    }
    return sum / Double(width * height)
}

/// Thread-safe record of what Download or export saved, standing in for Photos.
private final class SavedFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data] = []
    var all: [Data] { lock.withLock { stored } }
    func save(_ data: Data) { lock.withLock { stored.append(data) } }
    func save(_ data: [Data]) { lock.withLock { stored.append(contentsOf: data) } }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func fileExists(_ photo: RollPhoto) -> Bool {
    FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: photo.photoPath).path())
}

private func removeFiles(_ photos: [RollPhoto]) {
    for photo in photos {
        try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: photo.photoPath))
    }
}

// MARK: - Roll model and store

@MainActor
struct RollStoreTests {

    @Test func aRollPhotoRoundTripsItsLook() throws {
        let context = try makeContext()
        var look = FilmLook.stockDefaults(for: .portrait400)
        look.strengths.vignette = 0.6
        look.printStock = .matte
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let inserted = try RollViewModel.insert(original: photo(), look: look, capturedAt: captured, context: context)
        defer { removeFiles([inserted]) }

        let fetched = try #require(try context.fetch(FetchDescriptor<RollPhoto>()).first)
        #expect(fetched.id == inserted.id)
        #expect(fetched.look == look)
        #expect(fetched.capturedAt == captured)
        #expect(fetched.photoPath.hasPrefix("\(Constants.Roll.photosDirectoryName)/"))
        #expect(fileExists(fetched))
        #expect(RollViewModel.loadPhoto(for: fetched)?.size == CGSize(width: 96, height: 72))
    }

    @Test func aDamagedLookDataStillShowsThePhotoAsTheOriginal() {
        let row = RollPhoto(capturedAt: .now, photoPath: "Roll/x.jpg", look: .stockDefaults(for: .cine500T))
        row.lookData = Data("garbage".utf8)
        #expect(row.look == .original)
    }

    @Test func listsNewestCaptureFirst() {
        func row(_ seconds: TimeInterval) -> RollPhoto {
            RollPhoto(capturedAt: Date(timeIntervalSince1970: seconds), photoPath: "Roll/\(seconds).jpg", look: .original)
        }
        let old = row(100), middle = row(200), newest = row(300)
        #expect(RollViewModel.sorted([middle, old, newest]).map(\.capturedAt.timeIntervalSince1970) == [300, 200, 100])

        // A re-edit changes editedAt, never the order of different captures
        old.editedAt = .now
        #expect(RollViewModel.sorted([old, middle, newest]).first === newest)
    }

    @Test func reEditSavesTheLookAndNeverTouchesTheFile() throws {
        let context = try makeContext()
        let original = photo(0.3)
        let row = try RollViewModel.insert(original: original, look: .original, capturedAt: .now, context: context, now: Date(timeIntervalSince1970: 10))
        defer { removeFiles([row]) }
        let url = FileManager.documentsURL(forRelativePath: row.photoPath)
        let before = try Data(contentsOf: url)

        let edited = FilmLook.stockDefaults(for: .cine500T)
        try RollViewModel.update(row, look: edited, context: context, now: Date(timeIntervalSince1970: 99))

        #expect(row.look == edited)
        #expect(row.editedAt == Date(timeIntervalSince1970: 99))
        #expect(try Data(contentsOf: url) == before, "non-destructive: the original is the same bytes")
    }

    @Test func deleteRemovesTheFileAndTheRecord() throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        let other = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([other]) }
        #expect(fileExists(row))

        let path = row.photoPath
        try RollViewModel.delete(row, context: context)
        #expect(!FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: path).path()))
        let left = try context.fetch(FetchDescriptor<RollPhoto>())
        #expect(left.map(\.id) == [other.id])
    }

    @Test func clearRollRemovesEveryPhotoAndLeavesTheDiaryAlone() throws {
        let context = try makeContext()
        let rows = try (0..<3).map { _ in
            try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        }
        context.insert(DiaryEntry(photoPath: "Photos/keep.jpg", prompt: "P", response: "R"))
        context.insert(DailyStrip(entryIDs: [], isPhotobooth: true))
        try context.save()
        let paths = rows.map(\.photoPath)

        try RollViewModel.clearRoll(context: context)

        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
        for path in paths {
            #expect(!FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: path).path()))
        }
        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).count == 1)
    }

    @Test func selectionKeepsTapOrderAndRespectsTheStripLimit() {
        let rows = (0..<6).map { RollPhoto(capturedAt: Date(timeIntervalSince1970: Double($0)), photoPath: "Roll/\($0).jpg", look: .original) }
        let model = RollViewModel()
        for row in rows.prefix(4) { #expect(model.toggleSelection(of: row, limit: Constants.Roll.maxPhotosPerStrip)) }
        #expect(!model.toggleSelection(of: rows[4], limit: Constants.Roll.maxPhotosPerStrip), "a fifth photo is ignored")
        #expect(model.selectionCount == 4)
        #expect(!RollViewModel.canAddToStrip(selectedCount: 4))

        #expect(model.toggleSelection(of: rows[1], limit: Constants.Roll.maxPhotosPerStrip), "deselecting always works")
        #expect(model.selectedPhotos(in: rows).map(\.id) == [rows[0].id, rows[2].id, rows[3].id])
        #expect(RollViewModel.canAddToStrip(selectedCount: 3))

        // Export has no limit
        let exporter = RollViewModel()
        for row in rows { exporter.toggleSelection(of: row) }
        #expect(exporter.selectionCount == 6)
        exporter.endSelecting()
        #expect(!exporter.isSelecting && !exporter.hasSelection)
    }

    @Test func stripItemsLinkToTheCurrentLookAndCapAtFour() throws {
        let context = try makeContext()
        let look = FilmLook.stockDefaults(for: .cine500T)
        let rows = try (0..<5).map { _ in
            try RollViewModel.insert(original: photo(), look: look, capturedAt: .now, context: context)
        }
        defer { removeFiles(rows) }

        // v5-8: link, not copy — a look edited before generate shows up
        var edited = look
        edited.strengths.lightLeak = 0.9
        try RollViewModel.update(rows[0], look: edited, context: context)

        let items = RollViewModel.stripItems(from: rows)
        #expect(items.count == Constants.Roll.maxPhotosPerStrip)
        #expect(items[0].look == edited)
        #expect(items[1].look == look)
        #expect(items.allSatisfy { $0.image != nil && $0.entryID == nil && $0.caption.isEmpty })
        #expect(items[0].filmStock == .cine500T, "As shot falls back to the look's stock")
    }

    /// Pick from Roll keeps the whole look (print, B&W, strengths), the same
    /// strip item the Roll's own Generate builds.
    @MainActor
    @Test func aRollPhotoPickedIntoAStripKeepsItsFullLook() throws {
        let context = try makeContext()
        var look = FilmLook.stockDefaults(for: .portrait400)
        look.printStock = look.stock.availablePrints.last
        look.blackAndWhite = true
        look.strengths.grain = 1.2
        look.strengths.vignette = 0.7
        let row = try RollViewModel.insert(original: photo(), look: look, capturedAt: .now, context: context)
        defer { removeFiles([row]) }

        let booth = PhotoboothViewModel()
        booth.add(rollPhoto: row)
        let picked = try #require(booth.stripItems.first)
        let expected = try #require(RollViewModel.stripItems(from: [row]).first)

        #expect(booth.stripProgressText == "1 of 4")
        #expect(picked.look == look && picked.look == expected.look)
        #expect(picked.filmStock == expected.filmStock && picked.caption == expected.caption && picked.entryID == expected.entryID)
        #expect(picked.image?.size == expected.image?.size)

        // linked: an edit before Generate shows up
        var edited = look
        edited.strengths.halation = 0.3
        try RollViewModel.update(row, look: edited, context: context)
        let second = PhotoboothViewModel()
        second.add(rollPhoto: row)
        #expect(second.stripItems.first?.look == edited)

        booth.add(rollPhoto: row)
        #expect(booth.shots.count == 1, "the same photo can't take two slots")
    }

    @Test func exportSavesFullResolutionHEICInEachPhotosLook() async throws {
        let context = try makeContext()
        let rows = [
            try RollViewModel.insert(original: photo(0.5, size: CGSize(width: 160, height: 120)), look: .original, capturedAt: .now, context: context),
            try RollViewModel.insert(original: photo(0.5, size: CGSize(width: 200, height: 100)), look: .stockDefaults(for: .mono3200), capturedAt: .now, context: context),
        ]
        defer { removeFiles(rows) }
        let saved = SavedFiles()
        let model = RollViewModel()

        await model.export(rows, savePhotosData: { saved.save($0) })

        #expect(saved.all.count == 2)
        #expect(model.lastExportCount == 2 && !model.isExporting)
        #expect(pixelSize(of: saved.all[0]) == CGSize(width: 160, height: 120))
        #expect(pixelSize(of: saved.all[1]) == CGSize(width: 200, height: 100))
    }

    @Test func aFailedExportRaisesAnErrorAndSavesNothing() async throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([row]) }
        let errors = ErrorState()
        let model = RollViewModel()
        model.errorState = errors

        await model.export([row], savePhotosData: { _ in throw AppError.photoLibraryPermissionDenied })

        #expect(model.lastExportCount == 0)
        if case .photoLibraryPermissionDenied = errors.current {} else {
            Issue.record("expected the permission error, got \(String(describing: errors.current))")
        }
    }
}

// MARK: - PhotoEditViewModel: a fresh capture

@MainActor
struct PhotoEditStateTests {

    private func settledEdit(
        stock: StripCustomization.FilmStock = .portrait400,
        preview: UIImage? = nil
    ) -> PhotoEditViewModel {
        let edit = PhotoEditViewModel(preview: preview ?? photo(), stock: stock)
        edit.setDisplaySize(CGSize(width: 24, height: 24), scale: 2)
        return edit
    }

    @Test func startsFromTheCamerasStockOnStockDefaults() {
        let edit = PhotoEditViewModel(preview: photo(), stock: .cine500T)
        #expect(edit.look == .stockDefaults(for: .cine500T))
        #expect(!edit.isReEditing && !edit.isModified && !edit.canResetToStockDefaults)
        #expect(edit.outcome == nil)
    }

    @Test func quickEditsRenderOnlyTheLastOne() async throws {
        let edit = settledEdit(stock: .none, preview: photo(0.5))
        edit.setDisplaySize(CGSize(width: 16, height: 16), scale: 2)
        edit.selectStock(.daylight200)
        edit.selectStock(.cine500T)
        edit.selectStock(.mono400)
        edit.setStrength(0.25, for: .grain)
        #expect(edit.isRendering)
        #expect(edit.isDownloadDisabled, "Download waits for the render")
        await edit.renderSettled()

        #expect(edit.look.stock == .mono400 && edit.strength(of: .grain) == 0.25)
        #expect(!edit.isRendering)
        let rendered = try #require(edit.renderedPhoto)
        // 96×72 covering 32×32 pixels: the short side lands on 32
        #expect(min(rendered.cgImage?.width ?? 0, rendered.cgImage?.height ?? 0) == 32, "rendered at display size, not source size")
        #expect(rendered !== edit.photo)
    }

    @Test func holdToCompareShowsTheOriginalAndChangesNothingElse() async {
        let original = photo(0.5)
        let edit = settledEdit(preview: original)
        await edit.renderSettled()
        let lookBefore = edit.look
        let rendered = edit.renderedPhoto
        #expect(edit.displayedPhoto === rendered)

        edit.setComparing(true)
        #expect(edit.isComparing && edit.displayedPhoto === original)
        #expect(edit.look == lookBefore && !edit.isRendering)
        edit.setComparing(false)
        #expect(edit.displayedPhoto === rendered)
    }

    @Test func resetReturnsToTheStocksDefaultsAndKeepsTheStock() async {
        let edit = settledEdit(stock: .cine500T)
        edit.setStrength(1.4, for: .haze)
        edit.setStrength(0, for: .halation)
        edit.selectPrint(.matte)
        edit.setBlackAndWhite(true)
        #expect(edit.canResetToStockDefaults && edit.isModified)

        edit.resetToStockDefaults()
        #expect(edit.look == .stockDefaults(for: .cine500T))
        #expect(!edit.canResetToStockDefaults)
        await edit.renderSettled()
    }

    @Test func toolRulesFollowTheStock() {
        let edit = PhotoEditViewModel(preview: photo(), stock: .slide100)
        #expect(!edit.isPrintPickerVisible, "slide film is projection-only")
        edit.selectStock(.mono400)
        #expect(edit.isBlackAndWhiteLocked && edit.isBlackAndWhiteOn)
        edit.setBlackAndWhite(false)
        #expect(!edit.look.blackAndWhite, "the lock ignores writes")
        edit.selectStock(.daylight200)
        #expect(edit.isPrintPickerVisible && edit.availablePrints == [.lab, .cinema, .matte])
        edit.setStrength(7, for: .vignette)
        #expect(edit.strength(of: .vignette) == Constants.ImageProcessing.Film.Strength.sliderMaximum)
    }

    @Test func theSelectedToolIsEditorStateAndIdsRoundTrip() {
        let edit = PhotoEditViewModel(preview: photo(), stock: .daylight200)
        #expect(edit.tool == .film)
        edit.tool = .effect(.grain)
        #expect(edit.tool.id == "grain")
        let ids = ["exposure", "film", "print"] + FilmLook.Effect.allCases.map(\.rawValue)
        #expect(PhotoEditViewModel.Tool.allTools.map(\.id) == ids, "Exposure comes first")
        #expect(ids.map { PhotoEditViewModel.Tool(id: $0).id } == ids)
        #expect(PhotoEditViewModel.Tool(id: "nonsense") == .film)
    }

    @Test func exposureSnapsToThirdStopsReadsOutAndResets() async {
        let edit = settledEdit(stock: .daylight200)
        #expect(edit.exposure == 0 && edit.exposureReadout == "0 EV")
        edit.setExposure(0.3)
        #expect(edit.exposure == 1.0 / 3.0 && edit.exposureReadout == "+0.3 EV")
        edit.setExposure(-1)
        #expect(edit.exposureReadout == "\u{2212}1.0 EV" && edit.isModified)
        edit.setExposure(5)
        #expect(edit.exposure == 2 && edit.exposureReadout == "+2.0 EV")
        #expect(PhotoEditViewModel.exposureReadout(for: 2.0 / 3.0) == "+0.7 EV")

        // Switching stock keeps the exposure; reset returns it to 0
        edit.selectStock(.cine500T)
        #expect(edit.exposure == 2)
        #expect(edit.canResetToStockDefaults)
        edit.resetToStockDefaults()
        #expect(edit.exposure == 0 && edit.exposureReadout == "0 EV" && !edit.canResetToStockDefaults)
        await edit.renderSettled()
    }

    @Test func exposureAloneRendersWithStockOff() async {
        let edit = settledEdit(stock: .none, preview: photo(0.5))
        let original = edit.photo
        #expect(edit.renderedPhoto === original)
        edit.setExposure(1)
        await edit.renderSettled()
        #expect(edit.renderedPhoto !== original)
        #expect(meanLuma(edit.displayedPhoto) > meanLuma(original))
        edit.setExposure(0)
        await edit.renderSettled()
        #expect(edit.renderedPhoto === original, "back to 0 EV shows the untouched original")
    }

    @Test func isDevelopingPhotoIsTrueExactlyWhileTheRAWIsPending() async {
        let preview = photo(0.5)
        #expect(!PhotoEditViewModel(preview: preview, stock: .none).isDevelopingPhoto, "no RAW, nothing to wait for")
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let edit = PhotoEditViewModel(preview: preview, stock: .none, development: development)
        #expect(edit.isDevelopingPhoto)
        continuation.yield(photo(0.5, size: CGSize(width: 200, height: 150)))
        _ = await edit.developedPhoto()
        await Task.yield()
        #expect(!edit.isDevelopingPhoto)
    }

    @Test func theRenderDebounceIsShortUnderUITestFast() {
        let fast = ProcessInfo.processInfo.arguments.contains("-UITestFast")
        #expect(Constants.PhotoEdit.renderDebounce == (fast ? Constants.PhotoEdit.uiTestRenderDebounce : 0.12))
        #expect(Constants.PhotoEdit.uiTestRenderDebounce < 0.12)
    }

    @Test func theDevelopedRAWReplacesThePreview() async {
        let preview = photo(0.5)
        let developed = photo(0.5, size: CGSize(width: 200, height: 150))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let edit = PhotoEditViewModel(preview: preview, stock: .none, development: development)
        #expect(edit.photo === preview && edit.isDevelopingPhoto)

        continuation.yield(developed)
        let final = await edit.developedPhoto()
        await Task.yield()
        #expect(final === developed && edit.photo === developed)
        #expect(!edit.isDevelopingPhoto)
        #expect(edit.renderedPhoto === developed)
    }

    @Test func downloadWaitsForTheRAWSavesFullResolutionAndCreatesNoRollRecord() async throws {
        let context = try makeContext()
        let preview = photo(0.5, size: CGSize(width: 32, height: 24))
        let developed = photo(0.5, size: CGSize(width: 160, height: 120))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let saved = SavedFiles()
        let edit = PhotoEditViewModel(
            preview: preview, stock: .portrait400, development: development, savePhotoData: { saved.save($0) }
        )
        edit.setDisplaySize(CGSize(width: 10, height: 10), scale: 1)

        let download = Task { await edit.download() }
        await Task.yield()
        #expect(edit.isSavingDownload)
        continuation.yield(developed)
        await download.value

        #expect(saved.all.count == 1)
        #expect(pixelSize(of: try #require(saved.all.first)) == CGSize(width: 160, height: 120),
                "the developed RAW at full size, never the preview or the display render")
        #expect(edit.didSaveDownload && !edit.isSavingDownload)
        #expect(edit.outcome == nil, "Download stays on the screen")
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
    }

    @Test func downloadSavesTheCurrentLookNotTheStockDefault() async throws {
        let saved = SavedFiles()
        let source = photo(0.5, size: CGSize(width: 120, height: 90))
        let edit = PhotoEditViewModel(preview: source, stock: .portrait400, savePhotoData: { saved.save($0) })
        edit.setStrength(0, for: .grain)
        edit.setStrength(1.5, for: .vignette)
        await edit.download()

        let expected = try ImageProcessor.renderFullLook(
            of: source, look: edit.look, seed: StripGenerator.photoLookSeed(for: edit.captureDate)
        )
        let defaultLook = try ImageProcessor.renderFullLook(
            of: source, look: .stockDefaults(for: .portrait400), seed: StripGenerator.photoLookSeed(for: edit.captureDate)
        )
        let data = try #require(saved.all.first)
        let decoded = try #require(UIImage(data: data))
        #expect(abs(meanLuma(decoded) - meanLuma(expected)) < 2, "the edited look was saved")
        #expect(abs(meanLuma(decoded) - meanLuma(defaultLook)) > abs(meanLuma(decoded) - meanLuma(expected)),
                "closer to the edit than to the untouched stock default")
    }

    @Test func aFailedDownloadRaisesAnErrorAndShowsNoSavedState() async {
        let errors = ErrorState()
        let edit = PhotoEditViewModel(
            preview: photo(), stock: .none, savePhotoData: { _ in throw AppError.photoLibraryPermissionDenied }
        )
        edit.errorState = errors
        await edit.download()
        #expect(!edit.didSaveDownload)
        if case .photoLibraryPermissionDenied = errors.current {} else {
            Issue.record("expected the permission error, got \(String(describing: errors.current))")
        }
    }

    @Test func saveToRollStoresTheDevelopedOriginalAndTheLook() async throws {
        let context = try makeContext()
        let preview = photo(0.5, size: CGSize(width: 32, height: 24))
        let developed = photo(0.5, size: CGSize(width: 128, height: 96))
        let development = Task { developed }
        var finished: [PhotoEditViewModel.Outcome] = []
        let edit = PhotoEditViewModel(preview: preview, stock: .cine500T, development: development)
        edit.onFinish = { finished.append($0) }
        edit.setStrength(0.5, for: .lightLeak)

        #expect(await edit.saveToRoll(context: context))

        let row = try #require(try context.fetch(FetchDescriptor<RollPhoto>()).first)
        defer { removeFiles([row]) }
        #expect(row.look == edit.look)
        #expect(row.capturedAt == edit.captureDate)
        #expect(RollViewModel.loadPhoto(for: row)?.size == CGSize(width: 128, height: 96), "the RAW, not the preview")
        #expect(finished == [.saved] && edit.outcome == .saved)
        #expect(await edit.saveToRoll(context: context) == false, "a finished session can't save twice")
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).count == 1)
    }

    @Test func discardAndRetakeLeaveNothingBehind() async throws {
        let context = try makeContext()
        for ending in [PhotoEditViewModel.Outcome.discarded, .retaken] {
            let edit = PhotoEditViewModel(preview: photo(), stock: .portrait400)
            edit.setDisplaySize(CGSize(width: 8, height: 8), scale: 1)
            var finished: [PhotoEditViewModel.Outcome] = []
            edit.onFinish = { finished.append($0) }

            if ending == .discarded { edit.discard() } else { edit.retake() }
            edit.discard()  // a second ending is ignored

            #expect(finished == [ending])
            #expect(edit.outcome == ending)
        }
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
    }

    @Test func aFailedRollSaveRaisesAndKeepsTheSessionOpen() async throws {
        // A photo that can't be encoded makes the insert throw
        let context = try makeContext()
        let empty = UIImage()
        let errors = ErrorState()
        let edit = PhotoEditViewModel(preview: empty, stock: .none)
        edit.errorState = errors
        #expect(await edit.saveToRoll(context: context) == false)
        #expect(edit.outcome == nil && !edit.isSavingToRoll)
        if case .persistenceFailed = errors.current {} else {
            Issue.record("expected a persistence error, got \(String(describing: errors.current))")
        }
    }
}

// MARK: - PhotoEditViewModel: re-edit from the Roll

@MainActor
struct PhotoReEditTests {

    private func rollRow(look: FilmLook, in context: ModelContext) throws -> RollPhoto {
        try RollViewModel.insert(original: photo(0.4), look: look, capturedAt: Date(timeIntervalSince1970: 5_000), context: context)
    }

    @Test func opensOnTheSavedLookAndSeedsFromTheCaptureTime() throws {
        let context = try makeContext()
        var look = FilmLook.stockDefaults(for: .slide100)
        look.strengths.vignette = 0.5
        let row = try rollRow(look: look, in: context)
        defer { removeFiles([row]) }

        let edit = try #require(PhotoEditViewModel(editing: row))
        #expect(edit.isReEditing && edit.look == look && !edit.isDevelopingPhoto)
        #expect(edit.captureDate == row.capturedAt, "the same grain as every other render of this photo")
        #expect(!edit.isModified)
    }

    @Test func saveUpdatesTheLookInPlace() async throws {
        let context = try makeContext()
        let row = try rollRow(look: .stockDefaults(for: .portrait400), in: context)
        defer { removeFiles([row]) }
        let edit = try #require(PhotoEditViewModel(editing: row))
        edit.selectStock(.cine500T)
        edit.setStrength(0.8, for: .lightLeak)
        var finished: [PhotoEditViewModel.Outcome] = []
        edit.onFinish = { finished.append($0) }

        #expect(await edit.saveToRoll(context: context))

        #expect(row.look == edit.look && row.look.stock == .cine500T)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).count == 1, "updated, not duplicated")
        #expect(finished == [.saved])
    }

    @Test func discardLeavesThePhotoUnchanged() throws {
        let context = try makeContext()
        let original = FilmLook.stockDefaults(for: .portrait400)
        let row = try rollRow(look: original, in: context)
        defer { removeFiles([row]) }
        let edit = try #require(PhotoEditViewModel(editing: row))
        edit.selectStock(.mono3200)
        edit.setStrength(0, for: .halation)
        #expect(edit.isModified)

        edit.discard()

        #expect(row.look == original)
        #expect(fileExists(row))
        #expect(edit.outcome == .discarded)
    }

    @Test func deleteRemovesThePhotoAfterAConfirmedTap() throws {
        let context = try makeContext()
        let row = try rollRow(look: .original, in: context)
        let path = row.photoPath
        let edit = try #require(PhotoEditViewModel(editing: row))
        var finished: [PhotoEditViewModel.Outcome] = []
        edit.onFinish = { finished.append($0) }

        #expect(edit.deleteFromRoll(context: context))

        #expect(!FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: path).path()))
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
        #expect(finished == [.deleted])
    }

    @Test func deleteIsOnlyForReEdits() throws {
        let context = try makeContext()
        let edit = PhotoEditViewModel(preview: photo(), stock: .none)
        #expect(!edit.deleteFromRoll(context: context))
        #expect(edit.outcome == nil)
    }

    @Test func aMissingFileCannotOpen() throws {
        let context = try makeContext()
        let row = try rollRow(look: .original, in: context)
        removeFiles([row])
        #expect(PhotoEditViewModel(editing: row) == nil)
    }

    @Test func reEditDownloadRendersTheCurrentEditNotTheSavedLook() async throws {
        let context = try makeContext()
        let row = try rollRow(look: .original, in: context)
        defer { removeFiles([row]) }
        let saved = SavedFiles()
        let save: @Sendable (Data) async throws -> Void = { saved.save($0) }
        let edit = try #require(PhotoEditViewModel(editing: row, savePhotoData: save))
        edit.selectStock(.portrait400)

        await edit.download()

        #expect(saved.all.count == 1)
        #expect(row.look == .original, "Download changes nothing in the Roll")
        let data = try #require(saved.all.first)
        let image = try #require(UIImage(data: data))
        #expect(abs(meanLuma(image) - meanLuma(photo(0.4))) > 1, "film look applied")
    }
}

// MARK: - CameraViewModel presents the edit step

@MainActor
struct CameraPhotoEditPresentationTests {

    @Test func aPhotoCaptureOpensAnEditSessionFromTheCamerasStock() throws {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        camera.selectFilmStock(.mono400)
        let edit = camera.beginPhotoEdit(preview: photo(), stock: camera.filmStock)
        #expect(camera.photoEdit === edit)
        #expect(edit.look == .stockDefaults(for: .mono400))
    }

    @Test func thePresentationFlagKeepsTheCoverDownUntilTheViewExists() throws {
        // OPEN: frontend flips Constants.PhotoEdit.presentsEditStep with the view
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        camera.beginPhotoEdit(preview: photo(), stock: .none)
        #expect(camera.isPhotoEditPresented == Constants.PhotoEdit.presentsEditStep)
    }

    @Test func everyEndingReturnsToTheCamera() throws {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        for ending in [{ (edit: PhotoEditViewModel) in edit.discard() }, { $0.retake() }] {
            let edit = camera.beginPhotoEdit(preview: photo(), stock: .portrait400)
            camera.isPhotoEditPresented = true
            ending(edit)
            #expect(camera.photoEdit == nil && !camera.isPhotoEditPresented)
        }
    }

    @Test func aNewCaptureDiscardsAnUnfinishedSession() throws {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        let first = camera.beginPhotoEdit(preview: photo(), stock: .none)
        let second = camera.beginPhotoEdit(preview: photo(), stock: .none)
        #expect(first.outcome == .discarded)
        #expect(camera.photoEdit === second)
    }
}

// MARK: - v5.1: Continue to diary, linked entries, delete with entry

private func entries(_ context: ModelContext) throws -> [DiaryEntry] {
    try context.fetch(FetchDescriptor<DiaryEntry>())
}

private func fileExists(atRelative path: String) -> Bool {
    FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: path).path())
}

@MainActor
struct ContinueToDiaryTests {

    @Test func savesToTheRollThenHandsThePromptWhatItNeeds() async throws {
        let context = try makeContext()
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        let edit = camera.beginPhotoEdit(preview: photo(0.4), stock: .portrait400, captureDate: Date(timeIntervalSince1970: 7_000))
        #expect(edit.canContinueToDiary)

        #expect(await edit.continueToDiary(context: context))
        let rows = try context.fetch(FetchDescriptor<RollPhoto>())
        defer { removeFiles(rows) }
        let row = try #require(rows.first)
        #expect(rows.count == 1 && edit.outcome == .continuedToDiary)

        #expect(camera.photoEdit == nil && !camera.isPhotoEditPresented)
        #expect(camera.isEditorPresented)
        #expect(camera.pendingDiaryRollPhotoID == row.id)
        #expect(camera.pendingDiaryLook == row.look && camera.pendingDiaryStock == .portrait400)
        #expect(camera.pendingDiaryCaptureDate == row.capturedAt)
        #expect(camera.pendingDiaryDisplayImage != nil)

        camera.endDiaryPrompt()
        #expect(!camera.isEditorPresented && camera.pendingDiary == nil)
    }

    @Test func isNotAvailableInReEditOrAfterTheSessionEnded() async throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([row]) }
        let reEdit = try #require(PhotoEditViewModel(editing: row))
        #expect(!reEdit.canContinueToDiary)
        #expect(await !reEdit.continueToDiary(context: context))
        #expect(reEdit.outcome == nil && reEdit.diaryContinuation == nil)

        let fresh = PhotoEditViewModel(preview: photo(), stock: .none)
        fresh.discard()
        #expect(!fresh.canContinueToDiary)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).count == 1)
    }

    @Test func aLinkedEntryCopiesNoImageAndFollowsTheRollPhotosLook() async throws {
        let context = try makeContext()
        let edit = PhotoEditViewModel(preview: photo(0.4), stock: .daylight200)
        #expect(await edit.continueToDiary(context: context))
        let row = try #require(try context.fetch(FetchDescriptor<RollPhoto>()).first)
        defer { removeFiles([row]) }

        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(image: nil, rollPhotoID: row.id, includeText: false, context: context))
        let entry = try #require(try entries(context).first)
        #expect(entry.rollPhotoID == row.id && entry.isLinkedToRoll)
        #expect(entry.photoPath == row.photoPath, "no second copy of the image")
        #expect(entry.look == row.look && entry.response.isEmpty)
        #expect(RollViewModel.hasDiaryEntry(row, in: context))

        var edited = row.look
        edited.strengths.vignette = 0.3
        try RollViewModel.update(row, look: edited, context: context)
        #expect(entry.look == edited, "re-editing the photo updates the entry")
    }

    @Test func entriesWithoutALinkKeepTheirOwnFileAndLook() throws {
        let context = try makeContext()
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        var look = FilmLook.stockDefaults(for: .slide100)
        look.strengths.grain = 0.2
        #expect(diary.saveEntry(image: photo(), look: look, includeText: true, context: context))
        let entry = try #require(try entries(context).first)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }
        #expect(entry.rollPhotoID == nil && entry.look == look && entry.photoPath.hasPrefix("Photos/"))

        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([row]) }
        var other = row.look
        other.strengths.vignette = 0.9
        try RollViewModel.update(row, look: other, context: context)
        #expect(entry.look == look, "an old entry is not touched by Roll edits")
    }

    @Test func badgeLookupMarksOnlyPhotosWithAnEntry() async throws {
        let context = try makeContext()
        let linked = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        let plain = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([linked, plain]) }
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(image: nil, rollPhotoID: linked.id, includeText: false, context: context))

        #expect(RollViewModel.photoIDsWithDiaryEntry(in: context) == [linked.id])
        #expect(RollViewModel.linkedPhotoIDs(in: try entries(context)) == [linked.id])
        #expect(RollViewModel.hasDiaryEntry(linked, in: context) && !RollViewModel.hasDiaryEntry(plain, in: context))
        #expect(RollViewModel.linkedEntryCount(for: linked, in: context) == 1)
        #expect(RollViewModel.linkedEntryCount(in: context) == 1)
    }
}

@MainActor
struct RollDeleteWithEntryTests {

    private func linkedPair(_ context: ModelContext) throws -> (RollPhoto, DiaryEntry) {
        var look = FilmLook.stockDefaults(for: .portrait400)
        look.strengths.vignette = 0.4
        let row = try RollViewModel.insert(original: photo(0.3), look: look, capturedAt: Date(timeIntervalSince1970: 9_000), context: context)
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        _ = diary.saveEntry(image: nil, rollPhotoID: row.id, includeText: true, context: context)
        return (row, try #require(try entries(context).first))
    }

    @Test func deleteBothRemovesTheEntryAndThePhoto() throws {
        let context = try makeContext()
        let (row, _) = try linkedPair(context)
        let path = row.photoPath
        try RollViewModel.delete(row, entries: .deleteBoth, context: context)
        #expect(try entries(context).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
        #expect(!fileExists(atRelative: path))
    }

    @Test func keepEntryGivesItAnOwnCopyWithTheLookSnapshotted() throws {
        let context = try makeContext()
        let (row, entry) = try linkedPair(context)
        let look = row.look
        let rollPath = row.photoPath
        try RollViewModel.delete(row, entries: .keepEntry, context: context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }

        #expect(entry.rollPhotoID == nil && !entry.isLinkedToRoll)
        #expect(entry.photoPath != rollPath && entry.photoPath.hasPrefix("Photos/"))
        #expect(fileExists(atRelative: entry.photoPath) && !fileExists(atRelative: rollPath))
        #expect(entry.look == look && entry.lookSeedDate == row.capturedAt)
        #expect(DiaryViewModel.loadPhoto(for: entry) != nil)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
    }

    @Test func aPhotoWithoutAnEntryJustDeletes() throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        #expect(RollViewModel.linkedEntryCount(for: row, in: context) == 0)
        try RollViewModel.delete(row, context: context)
        #expect(!fileExists(row))
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
    }

    @Test(arguments: [RollViewModel.RollDeletion.keepEntry, .deleteBoth])
    func clearRollFollowsTheChoiceAndDefaultsToKeeping(choice: RollViewModel.RollDeletion) throws {
        let context = try makeContext()
        let (row, entry) = try linkedPair(context)
        let plain = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }
        #expect(RollViewModel.linkedEntryCount(in: context) == 1)

        try RollViewModel.clearRoll(entries: choice, context: context)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).isEmpty)
        #expect(!fileExists(row) && !fileExists(plain))
        if choice == .keepEntry {
            #expect(try entries(context).count == 1 && entry.rollPhotoID == nil && fileExists(atRelative: entry.photoPath))
        } else {
            #expect(try entries(context).isEmpty)
        }
    }

    @Test func clearRollKeepsEntriesByDefault() throws {
        let context = try makeContext()
        let (_, entry) = try linkedPair(context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }
        try RollViewModel.clearRoll(context: context)
        #expect(try entries(context).count == 1 && fileExists(atRelative: entry.photoPath))
    }
}


// MARK: - Stock and print previews (v5.2 M5)

@MainActor
struct PhotoPreviewTests {

    private func edit(stock: StripCustomization.FilmStock = .portrait400) -> PhotoEditViewModel {
        PhotoEditViewModel(preview: photo(0.5, size: CGSize(width: 160, height: 120)), stock: stock)
    }

    @Test func rendersEveryStockAndEveryAvailablePrintOfThisPhoto() async {
        let edit = edit()
        edit.requestPreviews(size: CGSize(width: 24, height: 24), scale: 2)
        await edit.previewsSettled()
        #expect(Set(edit.stockPreviews.keys) == Set(StripCustomization.FilmStock.allCases))
        #expect(Set(edit.printPreviews.keys) == Set(StripCustomization.FilmStock.portrait400.availablePrints))
        // Covers the requested pixel size, never enlarged beyond the photo
        let off = edit.stockPreviews[.none]
        #expect(off.map { min($0.size.width, $0.size.height) } == 48)
        // Different stocks look different
        #expect(meanLuma(edit.stockPreviews[.cine500T]!) != meanLuma(edit.stockPreviews[.mono400]!))
        // Stock Off has no print choice, slide film only the projection
        edit.selectStock(.none)
        edit.requestPreviews(size: CGSize(width: 24, height: 24), scale: 2)
        await edit.previewsSettled()
        #expect(edit.printPreviews.isEmpty)
    }

    @Test func previewsAreDeterministicAndCachedPerLookAndSize() async throws {
        let edit = edit()
        let size = CGSize(width: 20, height: 20)
        edit.requestPreviews(size: size, scale: 2)
        await edit.previewsSettled()
        let firstImage = try #require(edit.stockPreviews[.daylight200])
        let first = try #require(Raster(firstImage))
        #expect(edit.previewRenderCount == 1)

        // Same look and size: served from the cache, no render
        let cachedImage = edit.stockPreviews[.daylight200]
        edit.requestPreviews(size: size, scale: 2)
        await edit.previewsSettled()
        #expect(edit.previewRenderCount == 1 && edit.stockPreviews[.daylight200] === cachedImage)

        // Picking a stock changes only the print row: the stock row is reused
        edit.selectStock(.cine500T)
        edit.requestPreviews(size: size, scale: 2)
        await edit.previewsSettled()
        #expect(edit.previewRenderCount == 2)
        #expect(edit.stockPreviews[.daylight200] === cachedImage)

        // A different look (exposure) or size renders again
        edit.setExposure(1)
        edit.requestPreviews(size: size, scale: 2)
        await edit.previewsSettled()
        #expect(edit.previewRenderCount == 3)
        edit.requestPreviews(size: CGSize(width: 30, height: 30), scale: 2)
        await edit.previewsSettled()
        #expect(edit.previewRenderCount == 4)

        // Deterministic: a second view model with the same photo and capture date matches pixel for pixel
        let again = PhotoEditViewModel(preview: photo(0.5, size: CGSize(width: 160, height: 120)), stock: .portrait400, captureDate: edit.captureDate)
        again.requestPreviews(size: size, scale: 2)
        await again.previewsSettled()
        let againImage = try #require(again.stockPreviews[.daylight200])
        #expect(Raster(againImage) == first)
    }

    @Test func zeroSizeRequestsAreIgnored() async {
        let edit = edit()
        edit.requestPreviews(size: .zero, scale: 3)
        await edit.previewsSettled()
        #expect(edit.stockPreviews.isEmpty && edit.previewRenderCount == 0)
    }
}

// MARK: - Library accessors (v5.2 M6)

@MainActor
struct RollDaySectionTests {

    private func rollPhoto(_ date: Date) -> RollPhoto {
        RollPhoto(capturedAt: date, photoPath: "Roll/x.jpg", look: .original)
    }

    @Test func groupsByDayNewestFirstWithinAndAcross() {
        let calendar = Calendar.current
        let today = Date.now
        let earlierToday = calendar.startOfDay(for: today).addingTimeInterval(60)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let longAgo = calendar.date(byAdding: .day, value: -40, to: today) ?? today
        let a = rollPhoto(earlierToday), b = rollPhoto(today), c = rollPhoto(yesterday), d = rollPhoto(longAgo)

        let sections = RollViewModel.daySections([c, d, a, b])
        #expect(sections.count == 3)
        #expect(sections.map(\.id) == [today.startOfDay, yesterday.startOfDay, longAgo.startOfDay])
        #expect(sections[0].photos.map(\.id) == RollViewModel.sorted([a, b]).map(\.id))
        #expect(sections[0].title == "Today" && sections[1].title == "Yesterday")
        #expect(sections[2].title == longAgo.librarySectionTitle)
        #expect(RollViewModel.daySections([]).isEmpty)
    }
}

@MainActor
struct LinkedEntryCountTests {

    @Test func theIfKnownCountsMatchTheOldOnesWhenTheFetchWorks() async throws {
        let context = try makeContext()
        let row = try RollViewModel.insert(original: photo(), look: .original, capturedAt: .now, context: context)
        defer { removeFiles([row]) }
        context.insert(DiaryEntry(photoPath: row.photoPath, prompt: "p", response: "r", rollPhotoID: row.id))
        try context.save()
        #expect(RollViewModel.linkedEntryCountIfKnown(for: row, in: context) == 1)
        #expect(RollViewModel.linkedEntryCountIfKnown(in: context) == 1)
        #expect(RollViewModel.linkedEntryCount(for: row, in: context) == 1)
        #expect(RollViewModel.linkedEntryCount(in: context) == 1)
        let edit = try #require(PhotoEditViewModel(editing: row))
        #expect(edit.linkedEntryCountIfKnown(in: context) == 1)
        #expect(PhotoEditViewModel(preview: photo(), stock: .none).linkedEntryCountIfKnown(in: context) == 0)
    }

    @Test func aFailedFetchIsNilNotZero() {
        struct Boom: Error {}
        #expect(RollViewModel.knownCount(describing: "test") { throw Boom() } == nil)
        #expect(RollViewModel.knownCount(describing: "test") { 3 } == 3)
    }
}

// MARK: - Edit after each shot (v5.2)

@MainActor
struct EditAfterEachShotTests {

    @Test func defaultsOnAndFollowsTheSetting() throws {
        let defaults = try makeScratchDefaults()
        let camera = CameraViewModel(defaults: defaults)
        #expect(camera.editAfterEachShot)
        defaults.set(false, forKey: Constants.DefaultsKeys.editAfterEachShot)
        #expect(!camera.editAfterEachShot)
        defaults.set(true, forKey: Constants.DefaultsKeys.editAfterEachShot)
        #expect(camera.editAfterEachShot)
    }

    @Test func offSavesStraightToTheRollWithTheStockDefaultsAndNoEditor() async throws {
        let defaults = try makeScratchDefaults()
        defaults.set(false, forKey: Constants.DefaultsKeys.editAfterEachShot)
        let camera = CameraViewModel(defaults: defaults)
        let context = try makeContext()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = await camera.saveStraightToRoll(
            preview: photo(), stock: .cine500T, captureDate: date,
            development: Task { photo(0.4, size: CGSize(width: 200, height: 150)) }, context: context
        )
        let row = try #require(saved)
        defer { removeFiles([row]) }
        #expect(row.look == .stockDefaults(for: .cine500T))
        #expect(row.capturedAt == date)
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).count == 1)
        #expect(camera.photoEdit == nil && !camera.isPhotoEditPresented, "no editor opened")
        // The developed original is what was stored, not the preview
        let stored = try #require(RollViewModel.loadPhoto(for: row))
        #expect(stored.size.width == 200)
    }
}
