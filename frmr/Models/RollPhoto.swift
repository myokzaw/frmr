import Foundation
import SwiftData

/// One photo in the Roll (v5 F6): the original development plus the look it
/// is shown with. Non-destructive: the file at `photoPath` is never
/// film-processed, so the look can be re-edited indefinitely.
///
/// Migration: a new model type added to the container is a lightweight
/// additive schema change — existing stores open unchanged and gain an empty
/// RollPhoto table. Nothing here alters DiaryEntry or DailyStrip.
@Model
final class RollPhoto {
    var id: UUID
    /// When the shutter fired; seeds the photo's grain and light leak, so
    /// the editor, the Roll, strips and exports all show one pattern.
    var capturedAt: Date
    /// Relative path in Documents (like DiaryEntry), never an absolute URL.
    var photoPath: String
    /// JSON-encoded `FilmLook`. Stored as Data, not as a Codable attribute,
    /// so `FilmLook`'s tolerant decoding (older shapes, unknown prints)
    /// still applies if its fields ever change.
    var lookData: Data
    var editedAt: Date

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        photoPath: String,
        look: FilmLook,
        editedAt: Date = .now
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.photoPath = photoPath
        self.lookData = FilmLook.encoded(look) ?? Data()
        self.editedAt = editedAt
    }

    /// The look the photo is shown with. A damaged row reads as the
    /// original (stock Off) rather than failing to show.
    var look: FilmLook {
        get { FilmLook.decoded(from: lookData) }
        set { lookData = FilmLook.encoded(newValue) ?? lookData }
    }

    var lookSeedDate: Date { capturedAt }
}
