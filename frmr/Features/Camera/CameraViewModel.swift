import AVFoundation
import Observation
import SwiftUI
import UIKit

@Observable
final class CameraViewModel {
    enum Mode {
        case diary
        case photobooth
    }

    var errorState: ErrorState?

    private let captureSession = CaptureSession()
    @ObservationIgnored private let defaults: UserDefaults

    var mode: Mode = .diary
    var whiteBalance: WBMode = .auto
    // View state, not user data: resets on every camera appear (v3 F3)
    private(set) var isWhiteBalanceExpanded = false

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
    // View state like the WB list: collapsed on every camera appear
    private(set) var isFilmStockExpanded = false

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

    // Diary flow (v4 F10): a capture opens a review of the original photo,
    // which OK hands on to the entry editor. The JPEG preview appears
    // immediately; the processed RAW replaces it when ready. The review
    // object lives until the entry is saved, skipped or retaken.
    private(set) var review: DiaryReviewViewModel?
    var isReviewPresented = false
    var isEditorPresented = false

    /// The original photo the entry will save (never film-processed).
    var pendingDiaryImage: UIImage? { review?.photo }
    /// The stock chosen on the review screen; what `saveEntry` must store.
    var pendingDiaryStock: StripCustomization.FilmStock { review?.stock ?? .none }
    /// When the pending photo was taken; `saveEntry(capturedAt:)` stores it
    /// so the diary shows the grain the review showed (OBS-V4-7).
    var pendingDiaryCaptureDate: Date? { review?.captureDate }
    /// The pending photo in its chosen look, for the editor header.
    var pendingDiaryDisplayImage: UIImage? { review?.renderedPhoto ?? review?.photo }

    var session: AVCaptureSession { captureSession.session }

    var isDiaryMode: Bool { mode == .diary }
    var isPhotoboothMode: Bool { mode == .photobooth }
    var isShutterDisabled: Bool { isCapturing || isPermissionDenied }
    // Lens chips only make sense on a multi-lens back camera
    var isLensSelectorVisible: Bool { cameraPosition == .back && availableLenses.count > 1 }
    var isFlipCameraVisible: Bool { hasFrontCamera && !isPermissionDenied }

    func selectDiaryMode() { mode = .diary }
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
        // Tapping the viewfinder dismisses the expanded WB and Film lists
        // (v3 F3, v4 F9) — before the guard, so it works even if the preview
        // isn't up yet
        isWhiteBalanceExpanded = false
        isFilmStockExpanded = false
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
        // OPEN: WB persistence TBD — always reset to Auto on launch for now
        whiteBalance = .auto
        isWhiteBalanceExpanded = false
        isFilmStockExpanded = false
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

    // MARK: White balance (v3 F3 — collapsible)

    func selectWhiteBalance(_ mode: WBMode) {
        whiteBalance = mode
        captureSession.apply(whiteBalance: mode)
        // Never leave the list open after a selection — including re-selecting
        // the already active mode
        isWhiteBalanceExpanded = false
    }

    func toggleWhiteBalanceExpansion() {
        isWhiteBalanceExpanded.toggle()
        // Only one list open at a time (v4 F9)
        if isWhiteBalanceExpanded { isFilmStockExpanded = false }
    }

    // MARK: Film stock (v4 F9 — collapsible like white balance)

    func selectFilmStock(_ stock: StripCustomization.FilmStock) {
        filmStock = stock
        isFilmStockExpanded = false
    }

    func toggleFilmStockExpansion() {
        isFilmStockExpanded.toggle()
        if isFilmStockExpanded { isWhiteBalanceExpanded = false }
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

    func captureForDiary() async {
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
        beginReview(preview: preview, stock: stock, captureDate: captureDate, development: development)
    }

    /// Opens the review for a fresh capture (the seam captureForDiary and
    /// tests share). Until the review screen exists the flow goes straight
    /// to the editor with the camera's stock (Constants.Diary.presentsReviewStep).
    func beginReview(
        preview: UIImage,
        stock: StripCustomization.FilmStock,
        captureDate: Date = .now,
        development: Task<UIImage, Never>? = nil,
        savePhotoData: (@Sendable (Data) async throws -> Void)? = nil
    ) {
        review?.discard()
        let review = savePhotoData.map {
            DiaryReviewViewModel(
                preview: preview, stock: stock, captureDate: captureDate,
                development: development, savePhotoData: $0
            )
        } ?? DiaryReviewViewModel(preview: preview, stock: stock, captureDate: captureDate, development: development)
        review.errorState = errorState
        self.review = review
        if Constants.Diary.presentsReviewStep {
            isReviewPresented = true
        } else {
            isEditorPresented = true
        }
    }

    /// OK on the review screen: the chosen stock travels with the pending
    /// photo to the editor (`pendingDiaryStock`).
    func confirmReview() {
        guard review != nil else { return }
        isReviewPresented = false
        isEditorPresented = true
    }

    /// Retake on the review screen: the capture is dropped and the camera
    /// is back. A photo already downloaded stays in the camera roll.
    func retake() {
        review?.discard()
        review = nil
        isReviewPresented = false
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

    // The editor's save, skip and retake all end the pending capture
    func discardPendingDiaryImage() {
        retake()
    }

    private func capturePhoto() async -> CapturedPhoto? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Fired before the capture so the thunk lands with the shutter, not after
        Haptics.shutterFired()

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
