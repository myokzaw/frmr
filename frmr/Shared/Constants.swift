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

    // MARK: Diary interaction (v2 F8b)
    enum Diary {
        // Fast enough not to feel slow, slow enough to register as deliberate
        static let promptTypewriterInterval: TimeInterval = 0.03
    }

    // MARK: Camera
    static let jpegCompressionQuality: Float = 0.85
    // OPEN: WB persistence TBD — the setting exists but capture always resets
    // to Auto on launch until the decision lands (build notes)
    static let rememberWhiteBalanceDefault = false

    // MARK: Camera controls (v2 F1–F3, F6)
    enum Camera {
        // Delay before the single retry of a failed portrait-lock request
        static let orientationLockRetryDelay: TimeInterval = 0.3

        // Tap-to-focus indicator (F1)
        static let focusIndicatorSize: CGFloat = 72
        static let focusIndicatorStroke: CGFloat = 1.5
        static let focusIndicatorAppearScale: CGFloat = 1.2
        static let focusIndicatorAppearDuration: TimeInterval = 0.15
        static let focusIndicatorHoldDuration: TimeInterval = 0.5
        static let focusIndicatorFadeDuration: TimeInterval = 0.4
        // Total on-screen life of the indicator, after which the view model clears it
        static let focusIndicatorDuration: TimeInterval = 1.2
        // OPEN: v2-1 — lock focus once it settles, or stay in continuous auto?
        // Default is continuous (less jarring if the subject moves), so this
        // timeout is currently only the window the KVO observer stays attached.
        static let focusSettleDuration: TimeInterval = 2.0
        static let lockFocusAfterTap = false

        // Exposure compensation (F2)
        static let exposureBiasMin: Float = -2.0
        static let exposureBiasMax: Float = 2.0
        static let exposureDragScale: CGFloat = 80    // points of drag per 1 EV
        static let exposureIndicatorFadeDelay: TimeInterval = 1.0
        static let exposureIndicatorFontSize: CGFloat = 12
        static let exposureIndicatorSpacing: CGFloat = 4
        static let exposureIndicatorPadding: CGFloat = 12
        // OPEN: v2-2 — persist EV bias across launches? Default: no.
        static let persistExposureBias = false

        // Pinch-to-zoom (F3)
        static let zoomRampRate: Float = 4.0
        static let minZoomFactor: CGFloat = 1.0
        // Soft cap: devices go higher but quality degrades past this
        static let maxZoomFactor: CGFloat = 10.0

        // Animated preview grain (F6)
        // OPEN: v2-3 — benchmark on A15; disable if the viewfinder drops below 24fps
        static let animatedGrainEnabled = true
        static let grainRefreshInterval: TimeInterval = 0.083   // ~12fps
        static let liveGrainOpacity: CGFloat = 0.08
        static let liveGrainTileSize: CGFloat = 180             // noise tile is tiled to fill

        // Orientation: interface stays locked to portrait so the preview never
        // rotates (would shift crop/composition under the user); chrome
        // counter-rotates in place instead so it still reads upright.
        static let orientationRotationDuration: TimeInterval = 0.3
    }

    // MARK: CoreImage pipeline — translated from Iphone_Simple.xmp
    // Three values are marked OPEN and need tuning against real captures.
    enum ImageProcessing {
        static let rawNoiseReduction: Float = 0.3
        static let rawNoiseReductionSharpness: Float = 0.2

        // Tone curve — normalised from LR's 0–255 range
        // Shared anchor points (same in Simple and Sunset presets)
        static let toneCurveShadowInput: Float = 0.282
        static let toneCurveShadowOutput: Float = 0.239

        // Simple preset midtone (neutral, everyday default)
        static let toneCurveMidSimpleInput: Float = 0.820
        static let toneCurveMidSimpleOutput: Float = 0.824

        // Sunset preset midtone (slightly lifted, warmer feel)
        static let toneCurveMidSunsetInput: Float = 0.812
        static let toneCurveMidSunsetOutput: Float = 0.843

        static let colorContrast: Float = 1.055
        static let colorSaturation: Float = 1.070
        static let vibrance: Float = 0.07
        static let noiseLevel: Float = 0.02
        static let noiseSharpness: Float = 0.40

        // OPEN: tune these against real RAW captures before shipping (project.md §13 #5)
        static let unsharpRadius: Float = 0.8
        static let unsharpIntensity: Float = 0.3
        static let vignetteIntensity: Float = 0.25
        static let vignetteRadius: Float = 1.6
        static let warmPushKelvin: Float = 5800
        static let warmPushTint: Float = 8

        // Strip look filters (project.md §8)
        static let stripGrainIntensity: Float = 0.06

        // MARK: Luminosity-weighted grain (v2 F4)
        // A U-curve over the luminance mask: heavy grain in shadows, lightest in
        // midtones, heavy again (but less than shadows) in highlights. This is how
        // real film responds, and it's what stops synthetic grain reading as a
        // flat Photoshop texture.
        // Control points are evenly spaced across the 0–1 luminance domain.
        // OPEN: v2-4 — grain curve tuning; these need calibration against real RAW captures
        static let grainLuminanceCurve: [Float] = [1.0, 0.3, 0.8]
        // Softens the mask so grain doesn't cluster on hard edges
        static let grainMaskBlurRadius: Float = 1.0

        // MARK: Film stock profiles (v2 F5)
        // Bundles grain intensity, grain scale and a colour cast into one named
        // creative choice. The cast is applied *before* the grain pass so the
        // grain itself stays neutral-coloured.
        struct FilmStockProfile: Sendable {
            let grainIntensity: Float
            let grainScale: CGFloat
            /// Row-major 4×4 RGBA colour matrix, as consumed by CIColorMatrix.
            let colourMatrix: [CGFloat]

            var isNeutral: Bool { colourMatrix == FilmStockProfile.identityMatrix }

            static let identityMatrix: [CGFloat] = [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            ]

            // Fine, almost invisible grain. Clean, documentary feel.
            static let iso100 = FilmStockProfile(
                grainIntensity: 0.04,
                grainScale: 1.0,
                colourMatrix: identityMatrix
            )

            // Visible grain, classic 35mm look. The default.
            // OPEN: v2-5 — cast values are aesthetic estimates, calibrate on device
            static let iso400 = FilmStockProfile(
                grainIntensity: 0.12,
                grainScale: 1.5,
                colourMatrix: [
                    1.03, 0, 0, 0,
                    0, 1.01, 0, 0,
                    0, 0, 1.00, 0,
                    0, 0, 0, 1,
                ]
            )

            // Heavy grain. Pushed film, night photography feel.
            // OPEN: v2-5 — cast values are aesthetic estimates, calibrate on device
            static let iso3200 = FilmStockProfile(
                grainIntensity: 0.30,
                grainScale: 2.5,
                colourMatrix: [
                    1.04, 0, 0, 0,
                    0, 1.05, 0, 0,
                    0, 0, 0.98, 0,
                    0, 0, 0, 1,
                ]
            )
        }
    }

    // MARK: White balance presets (temperature K, tint)
    enum WhiteBalance {
        static let sunlight: (Float, Float) = (5500, 10)
        static let cloudy: (Float, Float) = (6500, 15)
        static let fluorescent: (Float, Float) = (4000, -20)
        static let shade: (Float, Float) = (7500, 20)
        static let tungsten: (Float, Float) = (3200, 0)
        static let manualMin: Float = 2500
        static let manualMax: Float = 8000
    }

    // MARK: Strip layout (project.md §10, logical points; rendered at renderScale)
    enum Strip {
        // OPEN: square crop vs original aspect TBD — square is the conservative default
        static let cellAspectRatio: CGFloat = 1.0
        static let width: CGFloat = 150
        static let paperBorder: CGFloat = 6      // white photobooth-paper border, all sides
        static let contentPadding: CGFloat = 4
        static let cellSpacing: CGFloat = 8
        static let captionSpacing: CGFloat = 3   // gap between a photo and its caption
        static let captionFontSize: CGFloat = 9
        static let captionMaxLines = 2
        static let dateFontSize: CGFloat = 8
        static let dateLetterSpacing: CGFloat = 0.12
        static let renderScale: CGFloat = 2
        static let emptySlotAlpha: CGFloat = 0.08

        // MARK: Film-edge detailing (v2 F7)
        // Sprocket holes are punched into the white paper border on both edges.
        static let sprocketHoleRadius: CGFloat = 3.5
        static let sprocketHoleCount = 2            // per cell, per side
        static let sprocketHoleInset: CGFloat = 3   // centre X, from the strip edge
        // Punched through to the dark backing behind the paper
        static let sprocketHoleColorHex = "001219"

        static let frameNumberFontSize: CGFloat = 6
        static let frameNumberColorHex = "EE9B00"   // amber
        static let frameNumberInset: CGFloat = 2    // gap below the photo edge

        // Secondary DX-code-style date stamp running up the right border.
        // Smaller than the bottom stamp so it fits inside the 6pt paper border;
        // the sprocket holes are punched over it, exactly like real edge printing.
        static let datestampRotationDegrees: CGFloat = -90
        static let edgeDateFontSize: CGFloat = 5
    }

    // MARK: Camera UI (project.md §2, screens 1 & 3)
    enum CameraUI {
        static let shutterOuterDiameter: CGFloat = 76
        static let shutterInnerDiameter: CGFloat = 64
        static let shutterRingWidth: CGFloat = 4
        static let shutterBottomPadding: CGFloat = 28
        static let chipFontSize: CGFloat = 12
        static let chipHorizontalPadding: CGFloat = 12
        static let chipVerticalPadding: CGFloat = 7
        static let chipSpacing: CGFloat = 8
        static let chipInactiveOpacity: CGFloat = 0.14
        static let modePillFontSize: CGFloat = 13
        static let modePillPadding: CGFloat = 4

        // Rotate-in-place chrome (replaces v3 F2/F4): every chip is a fixed
        // circle, so turning it about its centre never overflows its frame
        static let chipDiameter: CGFloat = 44
        static let chipIconSize: CGFloat = 16

        // v3 F3 — collapsible white balance
        static let wbExpandAnimationDuration: TimeInterval = 0.2

        // v3 F1 — device-side diagnosis switch: renders the live
        // rotation angle over the camera so a device photograph can prove
        // what actually reaches the views (DEBUG builds only)
        static let chromeDebugOverlayEnabled = false
        static let slotSize: CGFloat = 64
        static let slotCornerRadius: CGFloat = 8
        static let slotDashWidth: CGFloat = 1.5
        static let slotDashLength: CGFloat = 4
        static let slotBorderOpacity: CGFloat = 0.3
        static let slotSpacing: CGFloat = 10
        static let secondaryButtonSize: CGFloat = 44
        static let secondaryButtonCornerRadius: CGFloat = 9
        static let generateButtonVerticalPadding: CGFloat = 9
        static let disabledControlOpacity: CGFloat = 0.5
        static let captionFontSize: CGFloat = 11
        static let captionOpacity: CGFloat = 0.45
        static let captionMaxWidth: CGFloat = 300
        static let captionMinScale: CGFloat = 0.7
        static let permissionTextMaxWidth: CGFloat = 280
        static let permissionTextMinScale: CGFloat = 0.8

        // Landscape dock on the far right edge
        static let dockSpacing: CGFloat = 10
        static let dockTrailingPadding: CGFloat = 12
    }

    // MARK: Entry editor UI (project.md §2, screen 2)
    enum EditorUI {
        static let photoHeightFraction: CGFloat = 0.38
        static let promptFontSize: CGFloat = 25
        static let entryFontSize: CGFloat = 16
        static let charCountFontSize: CGFloat = 12
        static let cardCornerRadius: CGFloat = 12
        static let buttonCornerRadius: CGFloat = 10
        static let buttonPadding: CGFloat = 16
        static let entryMinHeight: CGFloat = 120
        static let linkFontSize: CGFloat = 14
        static let linkSpacing: CGFloat = 28
    }

    // MARK: Library UI (project.md §2, screen 5)
    enum LibraryUI {
        static let titleFontSize: CGFloat = 30
        static let thumbnailSize: CGFloat = 56
        static let thumbnailCornerRadius: CGFloat = 8
        static let excerptFontSize: CGFloat = 15
        static let sectionFontSize: CGFloat = 12
        static let tabFontSize: CGFloat = 14
        static let rowSpacing: CGFloat = 14
        static let stripThumbnailHeight: CGFloat = 220
    }

    // MARK: Full-screen detail viewers (entry photo / strip)
    enum DetailUI {
        static let closeButtonSize: CGFloat = 32
        static let closeIconSize: CGFloat = 14
        static let textPanelMaxHeight: CGFloat = 260
    }

    // MARK: Strip screen UI (project.md §2, screen 4)
    enum StripUI {
        static let swatchDiameter: CGFloat = 30
        static let swatchBorderWidth: CGFloat = 2
        static let actionCornerRadius: CGFloat = 10
        static let actionFontSize: CGFloat = 13
        static let previewShadowRadius: CGFloat = 24
        static let previewShadowOpacity: CGFloat = 0.25
    }

    // MARK: First-run walkthrough (v3 F5/F6)
    enum Onboarding {
        static let scrimOpacity: CGFloat = 0.55
        static let bubbleMaxWidth: CGFloat = 260
        static let bubbleCornerRadius: CGFloat = 12
        static let bubbleEdgeInset: CGFloat = 16       // keeps edge-anchored bubbles on screen
        static let bubbleTabGap: CGFloat = 12
        static let arrowLength: CGFloat = 44
        static let arrowStroke: CGFloat = 1.5
        static let stepTransitionDuration: TimeInterval = 0.25
        static let bubbleTitleFontSize: CGFloat = 16
        static let bubbleBodyFontSize: CGFloat = 14
        static let bubbleBodyOpacity: CGFloat = 0.7
        static let bubbleInnerSpacing: CGFloat = 8
        // The tab bar is UIKit-managed, so SwiftUI anchor preferences on
        // .tabItem labels never reach the preference system. The coach-mark
        // anchors come from equal-width proxies laid over the bar's icon band
        // instead; this is that band's UIKit-standard height above the bottom
        // safe-area inset.
        static let tabBarBaseHeight: CGFloat = 49
        // The floating tab bar is inset from the screen edges; the anchor
        // proxies are inset by this fraction of the screen width per side so
        // their thirds line up with the real icon centres.
        // OPEN: fitted against the iPhone 17 Pro simulator — verify on other widths
        static let tabBarEdgeFraction: CGFloat = 0.18
    }

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
    }
}
