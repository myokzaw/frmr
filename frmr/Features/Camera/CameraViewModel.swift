import AVFoundation
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Where the stock dial and shutter stack sit relative to the viewfinder
/// (v5.2 S1).
nonisolated enum ChromePlacement: Equatable, Sendable {
    /// Under a 3:4 viewfinder, on their own band (tall phones).
    case below
    /// Over the bottom of the viewfinder (short phones).
    case overlay
}

@Observable
final class CameraViewModel {
    /// Declaration order is the mode switch's order: Photo, Film strip
    /// (v5.1 F1: Diary is no longer a camera mode).
    enum Mode: CaseIterable {
        case photo
        case photobooth

        /// Accessibility labels; the switch itself is icon-only.
        var label: String {
            switch self {
            case .photo: return "Photo"
            case .photobooth: return "Film strip"
            }
        }
    }

    /// The app opens in Photo every launch (v5 F1, OPEN: v5-9). Diary and
    /// Film strip are chosen from the switch and last only for the session;
    /// the stored capture mode (`DefaultsKeys.captureMode`) no longer decides.
    static let launchMode: Mode = .photo

    /// The panels that share the one slot above the shutter (v5 F3).
    enum Panel: Equatable {
        case film
        case whiteBalance
        case exposure
    }

    var errorState: ErrorState?

    private let captureSession = CaptureSession()
    @ObservationIgnored private let defaults: UserDefaults

    var mode: Mode = CameraViewModel.launchMode
    var whiteBalance: WBMode = .auto

    // MARK: Panels (v3 F3, v4 F9, v5 F3)

    /// Which of Film / White balance / Exposure is open; at most one at a
    /// time. View state, not user data: resets on every camera appear.
    private(set) var openPanel: Panel?
    var isWhiteBalanceExpanded: Bool { openPanel == .whiteBalance }
    var isFilmStockExpanded: Bool { openPanel == .film }
    var isExposurePanelExpanded: Bool { openPanel == .exposure }

    /// Opens `panel`, closing whichever was open; opening the open one closes it.
    func togglePanel(_ panel: Panel) {
        openPanel = openPanel == panel ? nil : panel
    }

    func closePanels() {
        openPanel = nil
    }

    // MARK: Free white balance (v5 F3)

    /// The Kelvin and tint the sliders show. After a preset they are that
    /// preset's values; on Auto they rest at the manual starting point.
    private(set) var whiteBalanceKelvin: Float = Constants.Camera.whiteBalanceManualStartKelvin
    private(set) var whiteBalanceTint: Float = Constants.Camera.whiteBalanceManualStartTint
    /// True once a slider set the balance, so no preset is selected.
    private(set) var isWhiteBalanceCustom = false

    /// The preset to highlight; nil while a slider-set balance is active.
    /// White balance is off Auto: a preset other than Auto, or a custom
    /// Kelvin/tint. Drives the chip's amber state.
    var isWhiteBalanceAdjusted: Bool { whiteBalance != .auto || activeWhiteBalancePreset == nil }
    /// Exposure compensation is not 0 EV.
    var isExposureAdjusted: Bool { exposureBias != 0 }

    var activeWhiteBalancePreset: WBMode? { isWhiteBalanceCustom ? nil : whiteBalance }
    /// The chip's text: "AUTO", or the Kelvin in force ("5600K").
    var whiteBalanceChipText: String {
        Self.whiteBalanceChipText(mode: whiteBalance, isCustom: isWhiteBalanceCustom, kelvin: whiteBalanceKelvin)
    }

    /// The panel's Kelvin readout: "Auto" until a preset or slider sets one.
    var whiteBalanceKelvinText: String {
        Self.whiteBalanceReadoutIsAuto(mode: whiteBalance, isCustom: isWhiteBalanceCustom)
            ? "Auto" : "\(Int(CaptureSession.clampedKelvin(whiteBalanceKelvin).rounded()))K"
    }
    /// The panel's tint readout: "Auto", or "+12" / "0" / "-5".
    var whiteBalanceTintText: String {
        Self.whiteBalanceReadoutIsAuto(mode: whiteBalance, isCustom: isWhiteBalanceCustom)
            ? "Auto" : Self.tintReadoutText(for: whiteBalanceTint)
    }

    static func whiteBalanceReadoutIsAuto(mode: WBMode, isCustom: Bool) -> Bool {
        !isCustom && mode == .auto
    }

    static func tintReadoutText(for tint: Float) -> String {
        let rounded = Int(CaptureSession.clampedTint(tint).rounded())
        return rounded == 0 ? "0" : String(format: "%+d", rounded)
    }

    // MARK: Film stock (v4 F9)

    /// The stock the next capture is stored with, in both modes. Persisted
    /// as its own default, separate from the strip's (OPEN: v4-10,
    /// Constants.Camera.filmStockSharesStripDefault).
    private(set) var filmStock: StripCustomization.FilmStock {
        didSet {
            defaults.set(filmStock.rawValue, forKey: Constants.DefaultsKeys.cameraFilmStock)
            filmPreviewRenderer.setStock(filmStock)
            captureSession.setVideoFramesEnabled(showsFilmPreview)
        }
    }

    /// The live film viewfinder's engine (v4 F9). Embed with
    /// `FilmPreviewView(renderer:)` over the plain preview layer.
    @ObservationIgnored let filmPreviewRenderer = FilmPreviewRenderer()

    /// Whether the film viewfinder is drawn. Off shows the plain preview
    /// layer underneath, which is the same picture for less work.
    var showsFilmPreview: Bool { filmStock != .none }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.filmStock = Self.storedFilmStock(in: defaults)
        filmPreviewRenderer.setStock(filmStock)
        captureSession.setVideoFrameDelegate(filmPreviewRenderer.frameSink)
    }
    private(set) var cameraPosition: CameraPosition = .back
    private(set) var selectedLens: CameraLens = .wide
    private(set) var availableLenses: [CameraLens] = []
    private(set) var hasFrontCamera = false
    private(set) var isCapturing = false
    private(set) var isPermissionDenied = false

    // MARK: Manual controls (v2 F1–F3)

    // Where the focus square is drawn, in viewfinder coordinates. Cleared once
    // the indicator animation has run its course.
    private(set) var focusPoint: CGPoint?
    private(set) var exposureBias: Float = 0
    private(set) var isDraggingExposure = false
    // Keeps the readout on screen for a beat after the drag ends
    private(set) var isExposureLingering = false
    private(set) var zoomFactor: CGFloat = Constants.Camera.minZoomFactor

    // Converting a tap into a device point needs the preview layer's geometry.
    // Not observed: it's plumbing the view hands back, never rendered state.
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var zoomRange = Constants.Camera.minZoomFactor...Constants.Camera.minZoomFactor
    @ObservationIgnored private var pinchBaseZoom = Constants.Camera.minZoomFactor
    @ObservationIgnored private var exposureBiasAtDragStart: Float = 0
    @ObservationIgnored private var focusIndicatorTask: Task<Void, Never>?
    @ObservationIgnored private var exposureFadeTask: Task<Void, Never>?

    // The interface is locked to portrait (see InterfaceOrientationLock) so the
    // preview layer never rotates; this tracks how the phone is actually held
    // so the chrome can counter-rotate and still read upright.
    private(set) var uiRotationAngle: Angle = .zero
    @ObservationIgnored private var orientationObserver: NSObjectProtocol?

    // Visible while dragging, while a non-zero bias is applied (the user needs
    // to see the camera isn't metering normally), and briefly after release.
    var isExposureIndicatorVisible: Bool { isDraggingExposure || isExposureLingering || exposureBias != 0 }
    // A zero-width range means the camera can't zoom (typical of the front lens)
    var isZoomEnabled: Bool { zoomRange.upperBound > zoomRange.lowerBound }

    // MARK: Continue to diary (v5.1 F4/F5)

    /// What the prompt screen (`EntryEditorView`) needs after
    /// "Continue to diary": the photo has already been saved to the Roll.
    /// Cleared when the entry is saved, skipped or the flow is dropped.
    private(set) var pendingDiary: PhotoEditViewModel.DiaryContinuation?
    /// Drives the prompt screen's cover.
    var isEditorPresented = false

    /// The original photo (what a legacy, unlinked entry would copy).
    var pendingDiaryImage: UIImage? { pendingDiary?.photo }
    var pendingDiaryStock: StripCustomization.FilmStock { pendingDiary?.look.stock ?? .none }
    var pendingDiaryCaptureDate: Date? { pendingDiary?.capturedAt }
    var pendingDiaryLook: FilmLook { pendingDiary?.look ?? .original }
    /// The Roll photo the entry links to (v5.1-3); pass to `saveEntry(rollPhotoID:)`.
    var pendingDiaryRollPhotoID: UUID? { pendingDiary?.rollPhotoID }
    /// The photo in its edited look, for the prompt screen's header.
    /// Display-sized (long side <= `Constants.Diary.promptDisplayMaxPixels`),
    /// made once off the main thread when the continuation is set. Until it
    /// lands the prompt shows the editor's own display render.
    var pendingDiaryDisplayImage: UIImage? {
        pendingPromptImage ?? pendingDiary?.displayImage ?? pendingDiary?.photo
    }
    private(set) var pendingPromptImage: UIImage?
    @ObservationIgnored private var promptImageTask: Task<Void, Never>?

    /// Waits for the display copy, for tests.
    func promptImageSettled() async { await promptImageTask?.value }

    /// Long side capped at `maxPixels`, never enlarged, upright.
    nonisolated static func promptDisplayImage(from image: UIImage, maxPixels: CGFloat = CGFloat(Constants.Diary.promptDisplayMaxPixels)) -> UIImage {
        let width = image.size.width * image.scale, height = image.size.height * image.scale
        let longSide = max(width, height)
        guard longSide > 0 else { return image }
        let factor = min(1, maxPixels / longSide)
        return FilmPreviewThumbnails.source(
            from: image, coveringPixelSize: CGSize(width: width * factor, height: height * factor)
        )
    }

    var session: AVCaptureSession { captureSession.session }

    var isPhotoMode: Bool { mode == .photo }
    var isPhotoboothMode: Bool { mode == .photobooth }
    var isShutterDisabled: Bool { isCapturing || isPermissionDenied }
    // Lens chips only make sense on a multi-lens back camera
    var isLensSelectorVisible: Bool { cameraPosition == .back && availableLenses.count > 1 }
    var isFlipCameraVisible: Bool { hasFrontCamera && !isPermissionDenied }

    func selectPhotoMode() { mode = .photo }
    func selectPhotoboothMode() { mode = .photobooth }

    func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        applyCameraSelection()
    }

    func selectLens(_ lens: CameraLens) {
        selectedLens = lens
        applyCameraSelection()
    }

    private func applyCameraSelection() {
        captureSession.switchCamera(to: cameraPosition, lens: selectedLens)
        // The WB lock lives on the device, so re-apply it to the new camera
        captureSession.apply(whiteBalance: whiteBalance)
        // Focus, exposure and zoom are all per-device: start the new camera clean
        resetManualControls()
        Task { zoomRange = await captureSession.zoomRange() }
    }

    // MARK: Manual controls (v2 F1–F3)

    func registerPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
    }

    func userTapped(at location: CGPoint) {
        // Tapping the viewfinder dismisses the open Film, WB or EV panel
        // (v3 F3, v4 F9, v5 F3) — before the guard, so it works even if the
        // preview isn't up yet
        closePanels()
        guard let previewLayer else { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
        captureSession.setFocusAndExposure(atDevicePoint: devicePoint)

        focusPoint = location
        focusIndicatorTask?.cancel()
        focusIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Camera.focusIndicatorDuration))
            guard !Task.isCancelled else { return }
            self?.focusPoint = nil
        }
    }

    func exposureDragBegan() {
        guard !isDraggingExposure else { return }
        isDraggingExposure = true
        isExposureLingering = true
        exposureBiasAtDragStart = exposureBias
        exposureFadeTask?.cancel()
    }

    func exposureDragChanged(translationHeight: CGFloat) {
        exposureDragBegan()
        exposureBias = Self.exposureBias(fromDragHeight: translationHeight, base: exposureBiasAtDragStart)
        captureSession.setExposureBias(exposureBias)
    }

    func exposureDragEnded() {
        isDraggingExposure = false
        // The swipe is continuous; settling on a third-stop detent keeps it
        // in step with the EV chip's slider (v5 F3)
        let snapped = Self.snappedExposureBias(exposureBias)
        if snapped != exposureBias {
            exposureBias = snapped
            captureSession.setExposureBias(snapped)
        }
        exposureFadeTask?.cancel()
        exposureFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Camera.exposureIndicatorFadeDelay))
            guard !Task.isCancelled else { return }
            self?.isExposureLingering = false
        }
    }

    func pinchBegan() {
        pinchBaseZoom = zoomFactor
    }

    func pinchChanged(scale: CGFloat) {
        guard isZoomEnabled else { return }
        zoomFactor = CaptureSession.clampedZoom(
            pinchBaseZoom * scale,
            min: zoomRange.lowerBound,
            max: zoomRange.upperBound
        )
        captureSession.setZoom(zoomFactor, animated: false)
    }

    func resetZoom() {
        guard isZoomEnabled else { return }
        zoomFactor = zoomRange.lowerBound
        pinchBaseZoom = zoomFactor
        captureSession.setZoom(zoomFactor, animated: true)
    }

    // Drag up (negative height) brightens. Pure, so the mapping is unit-testable.
    static func exposureBias(fromDragHeight height: CGFloat, base: Float) -> Float {
        let delta = Float(-height / Constants.Camera.exposureDragScale)
        return min(max(base + delta, Constants.Camera.exposureBiasMin), Constants.Camera.exposureBiasMax)
    }

    // OPEN: v2-2 — EV bias is not persisted across launches, and resets on flip
    private func resetManualControls() {
        focusIndicatorTask?.cancel()
        focusPoint = nil
        exposureBias = 0
        exposureBiasAtDragStart = 0
        isDraggingExposure = false
        isExposureLingering = false
        exposureFadeTask?.cancel()
        captureSession.setExposureBias(0)
        zoomFactor = Constants.Camera.minZoomFactor
        pinchBaseZoom = Constants.Camera.minZoomFactor
    }

    func startCamera() async {
        let granted = await CaptureSession.ensurePermission()
        guard granted else {
            isPermissionDenied = true
            errorState?.raise(.cameraPermissionDenied)
            return
        }
        isPermissionDenied = false
        // OPEN: v5-4 — WB and EV are never persisted: every camera start
        // is Auto and 0 EV, on the device as well as in the state
        resetWhiteBalanceAndExposure()
        closePanels()
        availableLenses = CaptureSession.availableBackLenses()
        hasFrontCamera = CaptureSession.hasFrontCamera()
        captureSession.start()
        captureSession.setVideoFramesEnabled(showsFilmPreview)
        zoomRange = await captureSession.zoomRange()
        // Warm the Taptic Engine so the shutter tap doesn't lag the first capture
        Haptics.prepareShutter()
        startObservingOrientation()
    }

    func stopCamera() {
        captureSession.stop()
        stopObservingOrientation()
    }

    // MARK: Orientation (bugfix: rotate the chrome, not the preview)

    private func startObservingOrientation() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyOrientation(UIDevice.current.orientation)
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyOrientation(UIDevice.current.orientation)
        }
    }

    private func applyOrientation(_ orientation: UIDeviceOrientation) {
        uiRotationAngle = Self.rotationAngle(for: orientation, current: uiRotationAngle)
    }

    private func stopObservingOrientation() {
        if let orientationObserver {
            NotificationCenter.default.removeObserver(orientationObserver)
        }
        orientationObserver = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    // Returns an accumulated, unwrapped angle (never folded back to +/-90) so
    // SwiftUI animates the short way: landscapeLeft -> landscapeRight is a 180
    // turn, not the long way round. The target is measured from the nearest
    // equivalent of `current`, so 270 and -90 are the same pose and don't animate.
    // Flat/face orientations carry no usable rotation: hold the last angle.
    static func rotationAngle(for orientation: UIDeviceOrientation, current: Angle) -> Angle {
        let target: Double
        switch orientation {
        case .portrait: target = 0
        case .portraitUpsideDown: target = 180
        // UIDeviceOrientation's landscape cases name the side of the device
        // that's now "up"; the chrome rotates the opposite way to stay level.
        case .landscapeLeft: target = 90
        case .landscapeRight: target = -90
        default: return current
        }
        var delta = (target - current.degrees).truncatingRemainder(dividingBy: 360)
        if delta < 0 { delta += 360 }
        // Exactly 180 (portrait <-> upside-down, landscape <-> landscape) is
        // ambiguous; always take the positive arc so it is deterministic and
        // never flips direction between consecutive turns.
        if delta > 180 { delta -= 360 }
        return .degrees(current.degrees + delta)
    }

    // MARK: White balance (v3 F3 — collapsible; v5 F3 — Kelvin and tint)

    /// A preset tap in the collapsible list closes it (v3 F3).
    func selectWhiteBalance(_ mode: WBMode) {
        chooseWhiteBalancePreset(mode)
        // Never leave the list open after a selection — including re-selecting
        // the already active mode
        if openPanel == .whiteBalance { openPanel = nil }
    }

    /// The same preset, but the panel stays open: the Photo-mode panel
    /// keeps its Kelvin and tint sliders reachable after a preset.
    func chooseWhiteBalancePreset(_ mode: WBMode) {
        whiteBalance = mode
        isWhiteBalanceCustom = false
        if let preset = mode.temperatureAndTint {
            whiteBalanceKelvin = CaptureSession.clampedKelvin(preset.temperature)
            whiteBalanceTint = CaptureSession.clampedTint(preset.tint)
        } else {
            // Auto: the readouts return to the manual starting point (BUG-521-01)
            whiteBalanceKelvin = Constants.Camera.whiteBalanceManualStartKelvin
            whiteBalanceTint = Constants.Camera.whiteBalanceManualStartTint
        }
        captureSession.apply(whiteBalance: mode)
    }

    /// The Kelvin/tint sliders: a free white balance, clamped to 2500–9000 K
    /// and −50…+50, applied to the device on the session queue.
    func setWhiteBalance(kelvin: Float, tint: Float) {
        whiteBalanceKelvin = CaptureSession.clampedKelvin(kelvin)
        whiteBalanceTint = CaptureSession.clampedTint(tint)
        isWhiteBalanceCustom = true
        captureSession.apply(temperature: whiteBalanceKelvin, tint: whiteBalanceTint)
    }

    func setWhiteBalanceKelvin(_ kelvin: Float) {
        setWhiteBalance(kelvin: kelvin, tint: whiteBalanceTint)
    }

    func setWhiteBalanceTint(_ tint: Float) {
        setWhiteBalance(kelvin: whiteBalanceKelvin, tint: tint)
    }

    func toggleWhiteBalanceExpansion() {
        togglePanel(.whiteBalance)
    }

    /// "AUTO" while the device meters white balance itself, otherwise the
    /// Kelvin of the preset or slider setting.
    static func whiteBalanceChipText(mode: WBMode, isCustom: Bool, kelvin: Float) -> String {
        if !isCustom, mode == .auto { return "AUTO" }
        return "\(Int(CaptureSession.clampedKelvin(kelvin).rounded()))K"
    }

    // MARK: Exposure compensation (v5 F3)

    /// The EV chip's slider: a third-stop detent in −2…+2, applied to the
    /// device. Shares `exposureBias` with the swipe, so the two stay in sync.
    func setExposureBias(_ ev: Float) {
        let snapped = Self.snappedExposureBias(ev)
        exposureBias = snapped
        exposureBiasAtDragStart = snapped
        captureSession.setExposureBias(snapped)
    }

    /// Moves the bias by whole detents (negative = darker).
    func stepExposureBias(by steps: Int) {
        setExposureBias(exposureBias + Float(steps) * Constants.Camera.exposureStep)
    }

    func toggleExposurePanel() {
        togglePanel(.exposure)
    }

    /// The chip's text: "+0.3", "−1.7", "0.0".
    var exposureReadout: String { Self.exposureReadoutText(for: exposureBias) }

    /// The nearest third-stop detent inside the configured range.
    static func snappedExposureBias(_ ev: Float) -> Float {
        guard !ev.isNaN else { return 0 }
        let perStop = Float(Constants.Camera.exposureStepsPerStop)
        let detent = (ev * perStop).rounded() / perStop
        return min(max(detent, Constants.Camera.exposureBiasMin), Constants.Camera.exposureBiasMax)
    }

    static func exposureReadoutText(for ev: Float) -> String {
        // "+0.0" and "-0.0" read as plain zero
        abs(ev) < 0.05 ? "0.0" : String(format: "%+.1f", ev)
    }

    private func resetWhiteBalanceAndExposure() {
        whiteBalance = .auto
        isWhiteBalanceCustom = false
        whiteBalanceKelvin = Constants.Camera.whiteBalanceManualStartKelvin
        whiteBalanceTint = Constants.Camera.whiteBalanceManualStartTint
        captureSession.apply(whiteBalance: .auto)
        exposureBias = 0
        exposureBiasAtDragStart = 0
        captureSession.setExposureBias(0)
    }

    // MARK: Film stock (v4 F9 — collapsible like white balance)

    func selectFilmStock(_ stock: StripCustomization.FilmStock) {
        filmStock = stock
        if openPanel == .film { openPanel = nil }
    }

    func toggleFilmStockExpansion() {
        togglePanel(.film)
    }

    /// Collapsed shows only the active stock; expanded shows Off then the
    /// six stocks in declaration order.
    static func visibleStocks(
        expanded: Bool,
        selected: StripCustomization.FilmStock
    ) -> [StripCustomization.FilmStock] {
        expanded ? StripCustomization.FilmStock.allCases : [selected]
    }

    /// The camera's persisted stock; a missing or unknown value is Off.
    /// Also read by PhotoboothViewModel for gallery picks (OPEN: v4-12).
    nonisolated static func storedFilmStock(in defaults: UserDefaults) -> StripCustomization.FilmStock {
        .migrating(fromStoredValue: defaults.string(forKey: Constants.DefaultsKeys.cameraFilmStock))
    }

    // Collapsed shows only the active mode; expanded shows the full bank in
    // declaration order. Pure so the decision is unit-testable.
    static func visibleModes(expanded: Bool, selected: WBMode) -> [WBMode] {
        expanded ? WBMode.allCases : [selected]
    }

    // MARK: Chrome placement (v5.2 S1)

    /// `.below` when a 3:4 viewfinder (full width) plus the dial and shutter
    /// stack fits in the height left after the safe area, else `.overlay`.
    /// - Parameters:
    ///   - viewSize: the camera screen's full size, safe areas included.
    ///   - safeArea: its insets; the bottom one includes the tab bar when
    ///     the caller wants it reserved.
    static func chromePlacement(for viewSize: CGSize, safeArea: EdgeInsets) -> ChromePlacement {
        typealias C = Constants.Camera
        guard viewSize.width > 0, viewSize.height > 0 else { return .overlay }
        let viewfinderHeight = viewSize.width * C.viewfinderAspectHeightOverWidth
        let needed = viewfinderHeight + C.belowChromeStackHeight + C.belowChromeTopMargin
        let available = viewSize.height - safeArea.top - safeArea.bottom
        return needed <= available ? .below : .overlay
    }

    // MARK: Photo mode (v5 F4)

    /// The edit session for the last Photo-mode capture; lives until it is
    /// saved to the Roll, discarded or retaken.
    private(set) var photoEdit: PhotoEditViewModel?
    /// Drives the edit screen's cover. Stays false while
    /// `Constants.PhotoEdit.presentsEditStep` is off, so the app can never
    /// sit under a cover with no view behind it.
    var isPhotoEditPresented = false

    /// Whether a Photo-mode shot opens the editor (default) or goes straight
    /// to the Roll (`Constants.DefaultsKeys.editAfterEachShot`, v5.2).
    var editAfterEachShot: Bool {
        defaults.object(forKey: Constants.DefaultsKeys.editAfterEachShot) as? Bool ?? true
    }

    /// The shutter in Photo mode: capture, then open the edit step with the
    /// camera's stock on that stock's defaults. With "Edit after each shot"
    /// off and a `context`, the photo is saved straight to the Roll instead
    /// (no editor; the Roll's newest photo, and so the last-photo thumbnail,
    /// updates) and the saved haptic plays.
    func captureForPhoto(context: ModelContext? = nil) async {
        let stock = filmStock
        let captureDate = Date.now
        guard let photo = await capturePhoto() else { return }
        guard let preview = UIImage(data: photo.jpegData) else {
            errorState?.raise(.captureFailed(reason: "The photo data couldn't be read."))
            return
        }
        let development: Task<UIImage, Never>? = photo.rawData == nil ? nil : Task { [weak self] in
            guard let self else { return preview }
            return await self.processRAWIfPresent(photo, fallback: preview)
        }
        if !editAfterEachShot, let context {
            await saveStraightToRoll(
                preview: preview, stock: stock, captureDate: captureDate, development: development, context: context
            )
        } else {
            beginPhotoEdit(preview: preview, stock: stock, captureDate: captureDate, development: development)
        }
    }

    /// Saves a capture to the Roll on the camera's stock defaults without an
    /// editor (the seam `captureForPhoto` and tests share). Waits for the
    /// developed RAW so the stored original is never the JPEG preview.
    @discardableResult
    func saveStraightToRoll(
        preview: UIImage,
        stock: StripCustomization.FilmStock,
        captureDate: Date = .now,
        development: Task<UIImage, Never>? = nil,
        context: ModelContext
    ) async -> RollPhoto? {
        let original = await development?.value ?? preview
        do {
            let saved = try RollViewModel.insert(
                original: original, look: .stockDefaults(for: stock), capturedAt: captureDate, context: context
            )
            Haptics.play(.saved)
            return saved
        } catch let error as AppError {
            errorState?.raise(error)
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
        }
        return nil
    }

    /// Opens the edit step for a fresh capture (the seam `captureForPhoto`
    /// and tests share). A previous unfinished session is discarded.
    @discardableResult
    func beginPhotoEdit(
        preview: UIImage,
        stock: StripCustomization.FilmStock,
        captureDate: Date = .now,
        development: Task<UIImage, Never>? = nil,
        savePhotoData: (@Sendable (Data) async throws -> Void)? = nil
    ) -> PhotoEditViewModel {
        photoEdit?.discard()
        let edit = savePhotoData.map {
            PhotoEditViewModel(
                preview: preview, stock: stock, captureDate: captureDate,
                development: development, savePhotoData: $0
            )
        } ?? PhotoEditViewModel(preview: preview, stock: stock, captureDate: captureDate, development: development)
        edit.errorState = errorState
        edit.onFinish = { [weak self] outcome in self?.photoEditFinished(outcome, edit: edit) }
        photoEdit = edit
        if Constants.PhotoEdit.presentsEditStep {
            isPhotoEditPresented = true
        }
        return edit
    }

    /// Save, Discard and Retake all end here: back to the camera.
    func endPhotoEdit() {
        photoEdit = nil
        isPhotoEditPresented = false
    }

    private func photoEditFinished(_ outcome: PhotoEditViewModel.Outcome, edit: PhotoEditViewModel) {
        if outcome == .continuedToDiary, let continuation = edit.diaryContinuation {
            pendingDiary = continuation
            pendingPromptImage = nil
            promptImageTask?.cancel()
            let source = continuation.displayImage ?? continuation.photo
            promptImageTask = Task { [weak self] in
                let display = await Task.detached(priority: .userInitiated) { Self.promptDisplayImage(from: source) }.value
                guard !Task.isCancelled, let self, self.pendingDiary?.rollPhotoID == continuation.rollPhotoID else { return }
                self.pendingPromptImage = display
            }
            endPhotoEdit()
            isEditorPresented = true
        } else {
            endPhotoEdit()
        }
    }

    /// The prompt screen ended (entry saved or skipped) or was dropped:
    /// back to the camera. The Roll photo stays.
    func endDiaryPrompt() {
        pendingDiary = nil
        pendingPromptImage = nil
        promptImageTask?.cancel()
        isEditorPresented = false
    }

    /// The developed shot plus the stock chosen when the shutter fired
    /// (v4 F11), not when development finished.
    func captureForPhotobooth() async -> PhotoboothShot? {
        let stock = filmStock
        guard let photo = await capturePhoto() else { return nil }
        guard let preview = UIImage(data: photo.jpegData) else {
            errorState?.raise(.captureFailed(reason: "The photo data couldn't be read."))
            return nil
        }
        return PhotoboothShot(image: await processRAWIfPresent(photo, fallback: preview), filmStock: stock)
    }

    // The prompt screen's save and skip end the pending diary step
    func discardPendingDiaryImage() {
        endDiaryPrompt()
    }

    private func capturePhoto() async -> CapturedPhoto? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Fired before the capture so the thunk lands with the shutter, not after
        Haptics.play(.shutterAdvance)

        do {
            return try await captureSession.capturePhoto()
        } catch let error as AppError {
            errorState?.raise(error)
            return nil
        } catch {
            errorState?.raise(.captureFailed(reason: error.localizedDescription))
            return nil
        }
    }

    // Develops the RAW half of a capture; on any failure the JPEG preview is
    // kept and the user is told (spec: keep JPEG, raise rawProcessingFailed).
    private func processRAWIfPresent(_ photo: CapturedPhoto, fallback: UIImage) async -> UIImage {
        guard let rawData = photo.rawData else { return fallback }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.process(rawData: rawData)
            }.value
        } catch {
            errorState?.raise(.rawProcessingFailed)
            return fallback
        }
    }
}
