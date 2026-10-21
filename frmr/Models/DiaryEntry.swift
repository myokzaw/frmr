import Foundation
import SwiftData

@Model
final class DiaryEntry {
    var id: UUID
    var createdAt: Date
    var photoPath: String       // relative path in Documents — not a Data blob
    var prompt: String
    var response: String
    // v4 F11: the stock the photo was taken on. The photo at photoPath stays
    // the original development; the look is applied only when shown or
    // rendered. Optional so SwiftData's lightweight migration adds the
    // column with nil for every pre-F11 entry (nil = Off). Stored as the raw
    // string so a future stock rename migrates through FilmStock's own path.
    var filmStockRaw: String?
    // OBS-V4-7: when the shutter fired. Seeds the entry's grain and leak so
    // the diary shows the pattern the user reviewed and downloaded. Optional
    // for the same lightweight migration; older rows fall back to createdAt.
    var capturedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        photoPath: String,
        prompt: String,
        response: String,
        filmStock: StripCustomization.FilmStock = .none,
        capturedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.photoPath = photoPath
        self.prompt = prompt
        self.response = response
        self.filmStockRaw = filmStock.rawValue
        self.capturedAt = capturedAt
    }

    /// The entry's stock; entries saved before v4 F11 read as Off.
    // OPEN: v4-13 — changing an entry's stock after saving is not in v4
    // (Constants.Diary.entryStockIsEditable is false), so this is read-only
    var filmStock: StripCustomization.FilmStock {
        StripCustomization.FilmStock.migrating(fromStoredValue: filmStockRaw)
    }

    /// The date the entry's film look is seeded from: the capture, or the
    /// save date for entries from before it was stored.
    var lookSeedDate: Date { capturedAt ?? createdAt }
}
