import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// SwiftData persistence of the diary models.

// In-memory SwiftData store: proves the schema and save/fetch/delete paths
// work without touching the app's real store
struct PersistenceTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test func diaryEntryRoundTrips() throws {
        let context = try makeContext()
        let entry = DiaryEntry(
            photoPath: "Photos/test.jpg",
            prompt: "What made you take this picture?",
            response: "The light."
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiaryEntry>())

        #expect(fetched.count == 1)
        #expect(fetched[0].id == entry.id)
        #expect(fetched[0].photoPath == "Photos/test.jpg")
        #expect(fetched[0].prompt == "What made you take this picture?")
        #expect(fetched[0].response == "The light.")
    }

    @Test func dailyStripRoundTripsOrderedEntryIDs() throws {
        let context = try makeContext()
        let ids = [UUID(), UUID(), UUID(), UUID()]
        context.insert(DailyStrip(entryIDs: ids, isPhotobooth: false))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyStrip>())

        #expect(fetched.count == 1)
        #expect(fetched[0].entryIDs == ids)
        #expect(fetched[0].isPhotobooth == false)
        #expect(fetched[0].imageRelativePath == "Strips/\(fetched[0].id.uuidString).png")
    }

    @Test func deleteAllClearsBothModels() throws {
        // The path Settings' "Clear diary" relies on
        let context = try makeContext()
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R"))
        context.insert(DailyStrip(entryIDs: [], isPhotobooth: true))
        try context.save()

        try context.delete(model: DiaryEntry.self)
        try context.delete(model: DailyStrip.self)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).isEmpty)
    }

    @Test func entriesSortNewestFirstLikeTheLibraryQuery() throws {
        let context = try makeContext()
        let older = DiaryEntry(createdAt: .now.addingTimeInterval(-3600), photoPath: "Photos/old.jpg", prompt: "P", response: "old")
        let newer = DiaryEntry(createdAt: .now, photoPath: "Photos/new.jpg", prompt: "P", response: "new")
        context.insert(older)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.response) == ["new", "old"])
    }
}
