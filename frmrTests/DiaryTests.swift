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
        #expect(captured.stripProgressText == "4 of 4" && PhotoboothViewModel().stripProgressText == "0 of 4")
    }
}

// MARK: - OBS-V4-7: the diary shows the grain the review showed

@MainActor
struct EntryLookSeedTests {

    @Test func anEntrySavedFromAnEditRendersTheEditsGrain() async throws {
        let photo = solidImage(UIColor(white: 0.4, alpha: 1), size: CGSize(width: 120, height: 90))
        let captureDate = Date(timeIntervalSince1970: 1_790_000_123)
        let review = PhotoEditViewModel(preview: photo, stock: .mono3200, captureDate: captureDate)
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
            image: photo, filmStock: review.look.stock, capturedAt: review.captureDate, includeText: false, context: context
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
        #expect(try #require(shown.flatMap(PixelBuffer.init)) == reviewed, "same grain as the editor")
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
