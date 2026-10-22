import Foundation
import CoreGraphics

nonisolated extension Constants {
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
        // (v5-4 confirms: WB and EV reset on launch.)
        static let persistExposureBias = false
        // v5 F3: the EV chip's slider moves in third-stop detents
        static let exposureStepsPerStop = 3
        static let exposureStep: Float = 1 / Float(exposureStepsPerStop)

        // v5 F3 white balance fine-tune (Kelvin and tint sliders)
        static let whiteBalanceKelvinRange: ClosedRange<Float> = 2500...9000
        static let whiteBalanceTintRange: ClosedRange<Float> = -50...50
        // The Kelvin a manual white balance starts from when the first
        // slider is touched while on Auto
        static let whiteBalanceManualStartKelvin: Float = 5600
        static let whiteBalanceManualStartTint: Float = 0
        // OPEN: v5-4 — WB and EV reset on launch (not persisted)
        static let persistWhiteBalanceAndExposure = false
        // OPEN: v5-9 — the app always launches in Photo mode; the stored
        // capture mode (DefaultsKeys.captureMode) no longer decides it
        static let launchModeFollowsStoredCaptureMode = false

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

        // v4 F9 live film preview. The data output's connection is set to the
        // portrait angle once (never re-angled to the horizon, see
        // ios-camera-orientation); 90° is portrait for both cameras' sensors.
        static let portraitPreviewRotationAngle: CGFloat = 90
        // OPEN: v4-14 — 30 fps is the A15 target; measure on device
        static let filmPreviewFramesPerSecond = 30
        // OPEN: v4-10 — the camera's stock is its own default, not the strip's
        static let filmStockSharesStripDefault = false
        // OPEN: v4-12 — a gallery-picked photobooth photo takes the camera's
        // current stock (false would add it as Off)
        static let galleryPicksUseCameraStock = true
    }
}
