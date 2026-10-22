import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Roll (v5 F6)
    enum Roll {
        // OPEN: v5-8 — a Roll photo used in a strip is linked, not copied:
        // the strip renders its current look at generate time
        static let stripUsesLinkedLook = true
        static let maxPhotosPerStrip = Constants.entriesPerStrip
        // Folder (under Documents) holding the Roll originals
        static let photosDirectoryName = "Roll"
        // OPEN: v5-7 — "Clear roll" is separate from "Clear diary"
        static let clearRollIsSeparateFromClearDiary = true
    }
}
