import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: UserDefaults keys
    enum DefaultsKeys {
        static let appearanceMode = "appearanceMode"
        static let captureMode = "captureMode"
        // OPEN: WB persistence TBD — toggle exists in Settings but WB always resets to Auto for now
        static let rememberWhiteBalance = "rememberWhiteBalance"
        static let stripBackground = "stripDefaultBackground"
        // v2 F5 replaced the film-grain toggle with a film stock picker. The old
        // key is still read once so existing installs keep their grain preference.
        static let stripFilmStock = "stripDefaultFilmStock"
        static let stripFilmGrain = "stripDefaultFilmGrain"
        static let stripBlackAndWhite = "stripDefaultBlackAndWhite"
        // v4 F7 strip defaults. stripFilmStock keeps its key; v2 values in it
        // migrate on load (Constants.ImageProcessing.Film.legacyStockMapping).
        static let stripPrintStock = "stripDefaultPrintStock"
        static let stripHalation = "stripDefaultHalation"
        static let stripBloom = "stripDefaultBloom"
        static let stripLightLeak = "stripDefaultLightLeak"
        // v5 F5: haze is the renamed bloom. Its new key is read first; the
        // old bloom key is read once as a fallback (migration).
        static let stripHaze = "stripDefaultHaze"
        static let stripGrain = "stripDefaultGrain"
        static let stripVignette = "stripDefaultVignette"
        // v4 F9: the camera's film stock (raw FilmStock value; missing = Off)
        static let cameraFilmStock = "cameraFilmStock"
        // v5.2: after a Photo-mode shot, open the editor (true, default) or
        // save straight to the Roll with the camera's stock defaults
        static let editAfterEachShot = "editAfterEachShot"
        // v5.2 S7: the Core Haptics film-advance pattern on the shutter
        // (true, default); off = a single heavy impact
        static let filmAdvanceHaptics = "filmAdvanceHaptics"
        // v5.2.1 F-GRID: the viewfinder grid (raw CameraGrid value; missing = off)
        static let cameraGrid = "cameraGrid"
    }
}
