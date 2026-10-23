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
    // v5 F5: the whole look chosen on the review screen (print, B&W, effect
    // strengths) as JSON-encoded `FilmLook`. Optional for the same lightweight
    // migration; nil = the stock's defaults, which is exactly what every
    // pre-v5 entry was shown with. Only written when it differs from them.
    var lookData: Data?
    // v5.1 F5: the Roll photo this entry is about. Optional, additive
    // (lightweight migration: nil for every older entry, which keeps its own
    // photoPath and look). While set, the entry is a live link (v5.1-3): it
    // has no image copy of its own; `photoPath` mirrors the Roll photo's
    // file and `lookData` mirrors its current look (RollViewModel keeps
    // both in step on re-edit). Cleared when the entry is given its own
    // copy (v5.1-7 "keep the entry").
    var rollPhotoID: UUID?

    var isLinkedToRoll: Bool { rollPhotoID != nil }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        photoPath: String,
        prompt: String,
        response: String,
        filmStock: StripCustomization.FilmStock = .none,
        capturedAt: Date? = nil,
        look: FilmLook? = nil,
        rollPhotoID: UUID? = nil
    ) {
        self.rollPhotoID = rollPhotoID
        self.id = id
        self.createdAt = createdAt
        self.photoPath = photoPath
        self.prompt = prompt
        self.response = response
        self.filmStockRaw = (look?.stock ?? filmStock).rawValue
        self.capturedAt = capturedAt
        self.lookData = Self.storedLookData(for: look)
    }

    /// The stored form of `look`: nil when it is the stock's own defaults.
    static func storedLookData(for look: FilmLook?) -> Data? {
        guard let look, look != .stockDefaults(for: look.stock) else { return nil }
        return FilmLook.encoded(look)
    }

    /// The look the entry is shown with: the saved one, else its stock on
    /// the stock's defaults (every entry saved before v5).
    var look: FilmLook {
        get {
            guard let lookData else { return .stockDefaults(for: filmStock) }
            return FilmLook.decoded(from: lookData)
        }
        set {
            filmStockRaw = newValue.stock.rawValue
            lookData = Self.storedLookData(for: newValue)
        }
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
