import Foundation
import Observation

/// Picks which of today's diary entries go on the strip. Pick order is slot
/// order; the default is the latest `Constants.entriesPerStrip`, oldest first.
@Observable
final class EntryStripPickerViewModel {
    /// Today's entries, oldest first.
    let entries: [DiaryEntry]
    /// Pick order = slot order.
    private(set) var selectedIDs: [UUID]

    init(entries: [DiaryEntry]) {
        let today = entries
            .filter { Calendar.current.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt < $1.createdAt }
        self.entries = today
        self.selectedIDs = today.suffix(Constants.entriesPerStrip).map(\.id)
    }

    func toggle(_ entry: DiaryEntry) {
        if let index = selectedIDs.firstIndex(of: entry.id) {
            selectedIDs.remove(at: index)
        } else if selectedIDs.count < Constants.entriesPerStrip {
            selectedIDs.append(entry.id)
        }
    }

    /// 1-based slot, nil when not picked.
    func slotNumber(for entry: DiaryEntry) -> Int? {
        selectedIDs.firstIndex(of: entry.id).map { $0 + 1 }
    }

    var title: String { "\(selectedIDs.count) of \(Constants.entriesPerStrip) picked" }

    var canMakeStrip: Bool { !selectedIDs.isEmpty }

    /// Full and not picked.
    func isDisabled(_ entry: DiaryEntry) -> Bool {
        selectedIDs.count >= Constants.entriesPerStrip && !selectedIDs.contains(entry.id)
    }

    /// Picked entries in pick order, each with its full look.
    var stripItems: [StripItem] {
        selectedIDs.compactMap { id in entries.first { $0.id == id } }
            .map { Self.stripItem(for: $0) }
    }

    static func stripItem(for entry: DiaryEntry) -> StripItem {
        StripItem(
            image: DiaryViewModel.loadPhoto(for: entry),
            caption: entry.response,
            entryID: entry.id,
            look: entry.look
        )
    }
}
