import Foundation
import Observation
import Photos
import SwiftData
import UIKit

@Observable
final class LibraryViewModel {
    enum Tab: CaseIterable {
        case roll
        case entries
        case strips

        var label: String {
            switch self {
            case .roll: return "Roll"
            case .entries: return "Entries"
            case .strips: return "Strips"
            }
        }
    }

    /// Whether any entry was created today (the compile-today's-strip offer).
    static func hasEntriesToday(in entries: [DiaryEntry]) -> Bool {
        entries.contains { Calendar.current.isDateInToday($0.createdAt) }
    }

    var errorState: ErrorState?

    // Roll first and the default (v5 F6)
    var tab: Tab = .roll
    var isCompileStripPresented = false

    var isRollTabActive: Bool { tab == .roll }
    var isEntriesTabActive: Bool { tab == .entries }
    var isStripsTabActive: Bool { tab == .strips }

    func selectRollTab() { tab = .roll }
    func selectEntriesTab() { tab = .entries }
    func selectStripsTab() { tab = .strips }

    // MARK: Entry row text (v5.2 M6)

    /// The line a diary row previews: what the user wrote, else the prompt
    /// they answered; whitespace trimmed. Empty only when both are blank.
    static func excerpt(for entry: DiaryEntry) -> String {
        let response = entry.response.trimmingCharacters(in: .whitespacesAndNewlines)
        if !response.isEmpty { return response }
        return entry.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Oct 22, 2026 at 3:41 PM · Daylight 200": when it was taken (the
    /// shutter time, else when it was saved) and the stock it was shot on
    /// ("Original" for stock Off).
    static func metadataLine(for entry: DiaryEntry) -> String {
        let date = (entry.capturedAt ?? entry.createdAt).formatted(date: .abbreviated, time: .shortened)
        let stock = entry.filmStock
        return date + " \u{00B7} " + (stock == .none ? "Original" : stock.label)
    }

    /// Instance forwarders so views holding the view model can call either way.
    func excerpt(for entry: DiaryEntry) -> String { Self.excerpt(for: entry) }
    func metadataLine(for entry: DiaryEntry) -> String { Self.metadataLine(for: entry) }

    // Builds the strip source for "compile today's entries" (oldest first, so
    // the strip reads top-to-bottom in the order the day happened)
    static func todaysItems(from entries: [DiaryEntry]) -> [StripItem] {
        entries
            .filter { Calendar.current.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { EntryStripPickerViewModel.stripItem(for: $0) }
    }

    // MARK: Deleting strips

    /// Removes a strip's image file (a missing file is fine) and its record,
    /// then saves. Diary entries and Roll photos are untouched.
    func deleteStrip(_ strip: DailyStrip, context: ModelContext) throws {
        try Self.removeImageFile(for: strip)
        context.delete(strip)
        try Self.save(context)
    }

    /// Deletes every strip and its file.
    func clearStrips(context: ModelContext) throws {
        let strips: [DailyStrip]
        do {
            strips = try context.fetch(FetchDescriptor<DailyStrip>())
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
        for strip in strips {
            try Self.removeImageFile(for: strip)
            context.delete(strip)
        }
        try Self.save(context)
    }

    private static func removeImageFile(for strip: DailyStrip) throws {
        let url = FileManager.documentsURL(forRelativePath: strip.imageRelativePath)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    static func loadStripImage(for strip: DailyStrip) -> UIImage? {
        UIImage(contentsOfFile: FileManager.documentsURL(forRelativePath: strip.imageRelativePath).path())
    }

    // Explicit user action from the strip viewer: export an archived strip
    func saveStripToCameraRoll(_ strip: DailyStrip) async {
        guard let image = Self.loadStripImage(for: strip) else {
            errorState?.raise(.saveToLibraryFailed)
            return
        }
        do {
            try await PHPhotoLibrary.saveToCameraRoll([image])
        } catch let error as AppError {
            errorState?.raise(error)
        } catch {
            errorState?.raise(.saveToLibraryFailed)
        }
    }
}
