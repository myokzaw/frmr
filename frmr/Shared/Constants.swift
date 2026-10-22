import Foundation
import CoreGraphics

// nonisolated: pure immutable values, safely readable from any thread
// (the camera pipeline reads these off the main actor)
nonisolated enum Constants {

    // MARK: Diary
    static let promptSoftLimit = 120        // characters typed before the count indicator appears
    // OPEN: maximum entry character count TBD (project.md §13 #1) — 280 is the conservative default
    static let entryCharacterLimit = 280
    static let entriesPerStrip = 4

    // MARK: Camera
    static let jpegCompressionQuality: Float = 0.85
    // OPEN: WB persistence TBD — the setting exists but capture always resets
    // to Auto on launch until the decision lands (build notes)
    static let rememberWhiteBalanceDefault = false

}
