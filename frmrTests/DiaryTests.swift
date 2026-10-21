import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Diary: prompts, per-photo stock, review state and the entry look seed.

struct PromptSelectionTests {

    @Test func neverRepeatsThePreviousPromptImmediately() {
        var last: Int? = nil
        for _ in 0..<500 {
            let next = DiaryViewModel.nextPromptIndex(excluding: last, count: PromptBank.all.count)
            #expect(next != last)
            #expect((0..<PromptBank.all.count).contains(next))
            last = next
        }
    }

    @Test func singlePromptBankAlwaysReturnsTheOnlyIndex() {
        let index = DiaryViewModel.nextPromptIndex(excluding: 0, count: 1)

        #expect(index == 0)
    }

    @Test func promptBankMeetsMinimumSize() {
        // project.md §11 requires at least 50 prompts
        #expect(PromptBank.all.count >= 50)
    }
}

// MARK: - v4 F11: per-photo stock

struct PerPhotoStockModelTests {

    /// Every stock survives a SwiftData save and fetch (was a single Cine 500T
    /// case plus an init-only loop in the QA file).
    @Test(arguments: StripCustomization.FilmStock.allCases)
    func diaryEntryRoundTripsItsStock(stock: StripCustomization.FilmStock) throws {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R", filmStock: stock))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiaryEntry>())
        #expect(fetched.first?.filmStock == stock)
        #expect(fetched.first?.filmStockRaw == stock.rawValue)
    }

    // A row written before F11 has no stored stock: it reads as Off
    @Test func anEntryWithoutAStoredStockReadsAsOff() {
        let entry = DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R")
        #expect(entry.filmStock == .none)
        entry.filmStockRaw = nil
        #expect(entry.filmStock == .none, "a pre-F11 row (nil) must read as Off")
        entry.filmStockRaw = "iso400"
        #expect(entry.filmStock == .portrait400, "stored stocks migrate like every other stored stock")
        entry.filmStockRaw = "iso3200"
        #expect(entry.filmStock == .cine500T, "stored v2 values migrate like every stock")
    }

    /// A shot keeps its stock into the strip items, both ways of adding it
    /// (the capture path adds a PhotoboothShot), mixed stocks in order, and
    /// the original photo is kept rather than a filtered copy.
    @MainActor
    @Test func photoboothShotsCarryTheirStockIntoTheStrip() {
        let stocks: [StripCustomization.FilmStock] = [.slide100, .none, .daylight200, .mono3200]
        let photo = solidImage(.gray)

        let viewModel = PhotoboothViewModel()
        for stock in stocks { viewModel.add(photo, filmStock: stock) }
        #expect(viewModel.shot(at: 0)?.filmStock == .slide100)
        #expect(viewModel.image(at: 0) === photo, "the original photo is kept, not a filtered copy")
        #expect(viewModel.stripItems.map(\.filmStock) == stocks)

        let captured = PhotoboothViewModel()
        for stock in stocks { captured.add(PhotoboothShot(image: photo, filmStock: stock)) }
        #expect(captured.stripItems.map(\.filmStock) == stocks)
    }
}

// MARK: - v4 F10 / F13: diary review state

/// Thread-safe record of what Download saved, standing in for the camera roll.
private final class SavedPhotos: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data] = []
    var all: [Data] { lock.withLock { stored } }
    func save(_ data: Data) { lock.withLock { stored.append(data) } }
}

@MainActor
struct DiaryReviewStateTests {

    private func pixelSize(of data: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    @Test func quickStockTapsRenderOnlyTheLast() async throws {
        let review = DiaryReviewViewModel(preview: solidImage(.gray), stock: .none)
        review.setDisplaySize(CGSize(width: 16, height: 16), scale: 2)
        review.selectStock(.daylight200)
        review.selectStock(.cine500T)
        review.selectStock(.mono400)
        #expect(review.isRendering)
        #expect(review.isDownloadDisabled, "Download waits for the render")
        await review.renderSettled()

        #expect(review.stock == .mono400)
        #expect(!review.isRendering)
        let rendered = try #require(review.renderedPhoto.flatMap(PixelBuffer.init))
        let centre = rendered.rgb(x: rendered.width / 2, y: rendered.height / 2)
        #expect(abs(centre.r - centre.b) < 6, "the Mono 400 render won: \(centre)")
        #expect(rendered.width == 32, "rendered at display size, not source size")
    }

    @Test func theDevelopedRAWReplacesThePreview() async {
        let preview = solidImage(.gray)
        let developed = solidImage(.white, size: CGSize(width: 96, height: 96))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let review = DiaryReviewViewModel(preview: preview, stock: .none, development: development)
        #expect(review.photo === preview && review.isDevelopingPhoto)

        continuation.yield(developed)
        let final = await review.developedPhoto()
        await Task.yield()
        #expect(final === developed)
        #expect(review.photo === developed)
        #expect(!review.isDevelopingPhoto)
        #expect(review.renderedPhoto === developed, "Off shows the new original")
    }

    @Test func downloadWaitsForTheRAWAndSavesFullResolution() async throws {
        let preview = solidImage(.gray, size: CGSize(width: 32, height: 24))
        let developed = solidImage(.gray, size: CGSize(width: 160, height: 120))
        let (stream, continuation) = AsyncStream.makeStream(of: UIImage.self)
        let development = Task { for await image in stream { return image }; return preview }
        let saved = SavedPhotos()
        let review = DiaryReviewViewModel(
            preview: preview, stock: .portrait400, development: development, savePhotoData: { saved.save($0) }
        )
        review.setDisplaySize(CGSize(width: 10, height: 10), scale: 1)

        let download = Task { await review.downloadReview() }
        await Task.yield()
        #expect(review.isSavingDownload)
        continuation.yield(developed)
        await download.value

        #expect(saved.all.count == 1)
        #expect(pixelSize(of: try #require(saved.all.first)) == CGSize(width: 160, height: 120),
                "the developed RAW at full size, never the preview or the display render")
        #expect(review.didSaveDownload)
        #expect(!review.isSavingDownload)

        // OPEN v4-15 default: a second tap saves a second photo
        await review.downloadReview()
        #expect(saved.all.count == 2)
    }

    @Test func aFailedSaveRaisesAnErrorAndShowsNoSavedState() async {
        let errors = ErrorState()
        let review = DiaryReviewViewModel(
            preview: solidImage(.gray), stock: .none,
            savePhotoData: { _ in throw AppError.photoLibraryPermissionDenied }
        )
        review.errorState = errors
        await review.downloadReview()
        #expect(!review.didSaveDownload)
        if case .photoLibraryPermissionDenied = errors.current {} else {
            Issue.record("expected the permission error, got \(String(describing: errors.current))")
        }
    }

    @Test func okCarriesTheChosenStockToTheEditorAndRetakeDropsTheCapture() throws {
        let defaults = try makeScratchDefaults()
        let camera = CameraViewModel(defaults: defaults)
        camera.selectFilmStock(.daylight200)

        let preview = solidImage(.gray)
        camera.beginReview(preview: preview, stock: camera.filmStock)
        let review = try #require(camera.review)
        #expect(review.stock == .daylight200, "the review starts from the camera's stock")
        review.selectStock(.slide100)

        camera.confirmReview()
        #expect(camera.isEditorPresented && !camera.isReviewPresented)
        #expect(camera.pendingDiaryStock == .slide100)
        #expect(camera.pendingDiaryImage === preview, "the original is what gets saved")
        #expect(camera.filmStock == .daylight200, "changing the review stock leaves the camera's alone")

        camera.retake()
        #expect(camera.review == nil && camera.pendingDiaryImage == nil)
        #expect(!camera.isEditorPresented && !camera.isReviewPresented)
        #expect(camera.pendingDiaryStock == .none)
    }

    @Test func savingAnEntryStoresTheReviewedStock() throws {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(image: solidImage(.gray), filmStock: .cine500T, includeText: false, context: context))
        let entry = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        #expect(entry.filmStock == .cine500T)
        try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath))
    }
}

// MARK: - OBS-V4-7: the diary shows the grain the review showed

@MainActor
struct EntryLookSeedTests {

    @Test func anEntrySavedFromAReviewRendersTheReviewsGrain() async throws {
        let photo = solidImage(UIColor(white: 0.4, alpha: 1), size: CGSize(width: 120, height: 90))
        let captureDate = Date(timeIntervalSince1970: 1_790_000_123)
        let review = DiaryReviewViewModel(preview: photo, stock: .mono3200, captureDate: captureDate)
        review.setDisplaySize(CGSize(width: 60, height: 45), scale: 1)
        await review.renderSettled()
        let reviewed = try #require(review.renderedPhoto.flatMap(PixelBuffer.init))

        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(
            image: photo, filmStock: review.stock, capturedAt: review.captureDate, includeText: false, context: context
        ))
        let entry = try #require(try context.fetch(FetchDescriptor<DiaryEntry>()).first)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: entry.photoPath)) }
        #expect(entry.capturedAt == captureDate)
        #expect(entry.lookSeedDate == captureDate, "seeded from the capture, not the save")

        let shown = FilmLookCache().image(
            id: entry.id, stock: entry.filmStock,
            seed: StripGenerator.photoLookSeed(for: entry.lookSeedDate),
            pixelSize: CGSize(width: 60, height: 45)
        ) { photo }
        #expect(try #require(shown.flatMap(PixelBuffer.init)) == reviewed, "same grain as the review")
    }

    @Test func entriesFromBeforeTheCaptureDateFallBackToCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = DiaryEntry(createdAt: created, photoPath: "Photos/a.jpg", prompt: "P", response: "R")
        #expect(entry.capturedAt == nil)
        #expect(entry.lookSeedDate == created)
    }

    @Test func entryStockIsReadOnlyInV4() {
        #expect(!Constants.Diary.entryStockIsEditable)
        #expect(Constants.Camera.galleryPicksUseCameraStock)
    }
}
