import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Diary interaction (v2 F8b)
    enum Diary {
        // Fast enough not to feel slow, slow enough to register as deliberate
        static let promptTypewriterInterval: TimeInterval = 0.03

        // v4 F10 diary review. Stock chips can be tapped quickly; waiting
        // this long after the last tap renders once instead of per tap.
        static let reviewRenderDebounce: TimeInterval = 0.15
        // v4 F13 Download: how long the "Saved" state shows
        static let downloadSavedConfirmationDuration: TimeInterval = 1.5
        // HEIC quality for the saved film-look photo; matches the JPEG
        // capture quality so a download is no worse than the original
        static let downloadHEICQuality: Double = 0.85
        // OPEN: v4-15 — block a second Download of the same photo and stock?
        // Default: allow it; each tap saves one photo.
        static let blocksRepeatDownload = false
        // OPEN: v4-13 — an entry's stock is fixed once saved (not editable
        // in v4); DiaryEntry exposes it read-only
        static let entryStockIsEditable = false

        // v4 F11 display cache. OPEN: v4-11 — rendered copies are kept in
        // memory only (never written to disk); this caps that memory.
        static let displayCacheCostLimitBytes = 96 * 1024 * 1024
    }
}
