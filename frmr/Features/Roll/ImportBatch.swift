import Foundation

/// The state machine of one gallery import (F-122-E): which pick is open,
/// what was saved, skipped or unreadable, and when it is over. Pure, so every
/// rule is unit-testable; `GalleryImportSession` drives it and does the I/O.
///
/// Picks are addressed by index: the batch never holds a photo, so only the
/// one on screen is ever in memory.
nonisolated struct ImportBatch: Equatable {
    let total: Int
    /// The pick on screen (0-based); equals `total` once finished.
    private(set) var position = 0
    private(set) var savedCount = 0
    private(set) var skippedCount = 0
    private(set) var failedCount = 0
    private(set) var isCancelled = false

    init(total: Int) {
        self.total = max(total, 0)
    }

    var isFinished: Bool { isCancelled || position >= total }
    /// The index of the pick to show next; nil when the batch is over.
    var currentIndex: Int? { isFinished ? nil : position }
    /// "2 of 5" for the pick on screen.
    var counterText: String { "\(min(position + 1, total)) of \(total)" }
    /// Whether any pick follows the one on screen (Apply to rest needs one).
    var hasRemaining: Bool { !isFinished && position + 1 < total }

    mutating func markSaved() {
        guard !isFinished else { return }
        savedCount += 1
        position += 1
    }

    mutating func markSkipped() {
        guard !isFinished else { return }
        skippedCount += 1
        position += 1
    }

    /// An unreadable pick: counted, and the batch moves on.
    mutating func markFailed() {
        guard !isFinished else { return }
        failedCount += 1
        position += 1
    }

    /// Stops the batch. Photos already saved stay saved.
    mutating func cancel() {
        isCancelled = true
    }

    /// The look Apply to rest gives the remaining photos: this one's look
    /// without its crop and turns, which belong to one photo's framing.
    static func restLook(from look: FilmLook) -> FilmLook {
        look.with(crop: nil).with(quarterTurns: 0)
    }
}
