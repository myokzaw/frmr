import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Photo mode edit step (v5 F4)
    enum PhotoEdit {
        // OPEN: the edit screen (PhotoEditView) is the frontend's; until it
        // exists a Photo-mode capture is not presented (so the app can never
        // sit under a cover with no view). Flipped by frontend with lead approval.
        static let presentsEditStep = true
        // Slider drags render once per this pause, last value wins
        // (shorter under the DEBUG launch argument -UITestFast)
        static var renderDebounce: TimeInterval {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestFast") { return uiTestRenderDebounce }
            #endif
            return 0.12
        }
        #if DEBUG
        static let uiTestRenderDebounce: TimeInterval = 0.02
        #endif
        // Download "Saved" confirmation, same as the diary review
        static let downloadSavedConfirmationDuration: TimeInterval = 1.5
        // Roll originals are re-edited and re-encoded later, so they are
        // stored one notch above the capture quality
        static let rollPhotoJPEGQuality: Double = 0.92
    }
}
