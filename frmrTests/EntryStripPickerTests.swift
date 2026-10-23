import Foundation
import Testing
@testable import frmr

struct EntryStripPickerTests {

    private func makeEntries(_ count: Int, look: FilmLook? = nil) -> [DiaryEntry] {
        (0..<count).map { index in
            DiaryEntry(createdAt: Date.now.addingTimeInterval(Double(index - 20)), photoPath: "missing-\(index).jpg",
                       prompt: "p", response: "r\(index)", look: look)
        }
    }

    @Test func defaultsToLatestFourOldestFirst() {
        let entries = makeEntries(6)
        let model = EntryStripPickerViewModel(entries: entries.reversed())
        #expect(model.entries.map(\.id) == entries.map(\.id))
        #expect(model.selectedIDs == entries.suffix(4).map(\.id))
        #expect(model.slotNumber(for: entries[2]) == 1)
        #expect(model.slotNumber(for: entries[5]) == 4)
        #expect(model.slotNumber(for: entries[0]) == nil)
    }

    @Test func unpickRenumbersLaterPicks() {
        let entries = makeEntries(6)
        let model = EntryStripPickerViewModel(entries: entries)
        model.toggle(entries[3])
        #expect(model.slotNumber(for: entries[2]) == 1)
        #expect(model.slotNumber(for: entries[4]) == 2)
        #expect(model.slotNumber(for: entries[5]) == 3)
        model.toggle(entries[0])
        #expect(model.slotNumber(for: entries[0]) == 4)
    }

    @Test func limitsToFour() {
        let entries = makeEntries(6)
        let model = EntryStripPickerViewModel(entries: entries)
        #expect(model.isDisabled(entries[0]))
        model.toggle(entries[0])
        #expect(model.selectedIDs.count == 4)
        #expect(model.slotNumber(for: entries[0]) == nil)
        #expect(!model.isDisabled(entries[5]))
    }

    @Test func titleAndCanMakeStrip() {
        let entries = makeEntries(2)
        let model = EntryStripPickerViewModel(entries: entries)
        #expect(model.title == "2 of 4 picked")
        #expect(model.canMakeStrip)
        model.toggle(entries[0])
        model.toggle(entries[1])
        #expect(model.title == "0 of 4 picked")
        #expect(!model.canMakeStrip)
    }

    @Test func stripItemsFollowPickOrderAndCarryTheLook() {
        let look = FilmLook(stock: .portrait400, blackAndWhite: true, exposure: 0.5)
        let entries = makeEntries(3, look: look)
        let model = EntryStripPickerViewModel(entries: entries)
        model.toggle(entries[0])
        model.toggle(entries[0])
        #expect(model.stripItems.map(\.entryID) == [entries[1].id, entries[2].id, entries[0].id])
        #expect(model.stripItems.allSatisfy { $0.look == look })
    }
}

import SwiftData

struct StripDeletionTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func insertStrip(_ context: ModelContext, writeFile: Bool = true) throws -> DailyStrip {
        let strip = DailyStrip(entryIDs: [], isPhotobooth: true)
        context.insert(strip)
        if writeFile {
            _ = try FileManager.createStripsDirectory()
            try Data([1, 2, 3]).write(to: FileManager.documentsURL(forRelativePath: strip.imageRelativePath))
        }
        return strip
    }

    private func exists(_ strip: DailyStrip) -> Bool {
        FileManager.default.fileExists(atPath: FileManager.documentsURL(forRelativePath: strip.imageRelativePath).path())
    }

    @Test func deleteRemovesOneStripAndItsFileOnly() throws {
        let context = try makeContext()
        let doomed = try insertStrip(context)
        let kept = try insertStrip(context)
        defer { try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: kept.imageRelativePath)) }
        try context.save()

        try LibraryViewModel().deleteStrip(doomed, context: context)

        #expect(!exists(doomed))
        #expect(exists(kept))
        let left = try context.fetch(FetchDescriptor<DailyStrip>())
        #expect(left.map(\.id) == [kept.id])
    }

    @Test func clearRemovesAllStripsAndKeepsEntries() throws {
        let context = try makeContext()
        let strips = try [insertStrip(context), insertStrip(context)]
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R"))
        try context.save()

        try LibraryViewModel().clearStrips(context: context)

        #expect(strips.allSatisfy { !exists($0) })
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).count == 1)
    }

    @Test func missingFileIsNotAnError() throws {
        let context = try makeContext()
        let strip = try insertStrip(context, writeFile: false)
        try context.save()
        try LibraryViewModel().deleteStrip(strip, context: context)
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).isEmpty)
    }
}
