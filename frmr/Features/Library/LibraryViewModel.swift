import Foundation
import Observation
import Photos
import UIKit

@Observable
final class LibraryViewModel {
    enum Tab {
        case entries
        case strips
    }

    var errorState: ErrorState?

    var tab: Tab = .entries
    var isCompileStripPresented = false

    var isEntriesTabActive: Bool { tab == .entries }
    var isStripsTabActive: Bool { tab == .strips }

    func selectEntriesTab() { tab = .entries }
    func selectStripsTab() { tab = .strips }

    // Builds the strip source for "compile today's entries" (oldest first, so
    // the strip reads top-to-bottom in the order the day happened)
    static func todaysItems(from entries: [DiaryEntry]) -> [StripItem] {
        entries
            .filter { Calendar.current.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
            .map { entry in
                StripItem(
                    image: DiaryViewModel.loadPhoto(for: entry),
                    caption: entry.response,
                    entryID: entry.id,
                    filmStock: entry.filmStock
                )
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
