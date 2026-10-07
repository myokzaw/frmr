import Foundation
import SwiftData

@Model
final class DailyStrip {
    var id: UUID
    var createdAt: Date
    var entryIDs: [UUID]        // ordered references to DiaryEntry ids; empty for photobooth strips
    var isPhotobooth: Bool      // true = photobooth strip, false = diary strip

    init(id: UUID = UUID(), createdAt: Date = .now, entryIDs: [UUID], isPhotobooth: Bool) {
        self.id = id
        self.createdAt = createdAt
        self.entryIDs = entryIDs
        self.isPhotobooth = isPhotobooth
    }

    // Rendered strip PNGs live at a path derived from the id, so the model
    // doesn't need to store a file path.
    var imageRelativePath: String {
        "Strips/\(id.uuidString).png"
    }
}
