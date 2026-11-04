import Foundation
import SwiftData

/// One photo in the Roll (v5 F6): the original development plus the look it
/// is shown with. Non-destructive: the file at `photoPath` is never
/// film-processed, so the look can be re-edited indefinitely.
///
/// Migration: a new model type added to the container is a lightweight
/// additive schema change — existing stores open unchanged and gain an empty
/// RollPhoto table. Nothing here alters DiaryEntry or DailyStrip.
///
/// Migration (F-122-E): `sourceRaw` is a new stored attribute with an
/// inline default ("camera"), so SwiftData's lightweight migration opens
/// every existing store and fills old rows with that default. No custom
/// migration stage is needed.
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
    /// `Source.rawValue`; read through `source`. The inline default is what
    /// lightweight migration gives rows saved before 1.2.2.
    var sourceRaw: String = Source.camera.rawValue

    /// Where the photo came from (F-122-E): shot in the app, or imported
    /// from the gallery.
    enum Source: String {
        case camera
        case imported
    }

    init(
        id: UUID = UUID(),
        capturedAt: Date,
        photoPath: String,
        look: FilmLook,
        editedAt: Date = .now,
        source: Source = .camera
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.photoPath = photoPath
        self.lookData = FilmLook.encoded(look) ?? Data()
        self.editedAt = editedAt
        self.sourceRaw = source.rawValue
    }

    /// An unknown or missing value reads as camera, like every old row.
    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .camera }
        set { sourceRaw = newValue.rawValue }
    }

    /// The look the photo is shown with. A damaged row reads as the
    /// original (stock Off) rather than failing to show.
    var look: FilmLook {
        get { FilmLook.decoded(from: lookData) }
        set { lookData = FilmLook.encoded(newValue) ?? lookData }
    }

    var lookSeedDate: Date { capturedAt }
}
