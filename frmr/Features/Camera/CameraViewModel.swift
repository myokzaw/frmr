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

    var mode: Mode = .diary
    var whiteBalance: WBMode = .auto
    // View state, not user data: resets on every camera appear (v3 F3)
    private(set) var isWhiteBalanceExpanded = false
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

    // Diary flow: a capture sets this and presents the entry editor. The JPEG
    // preview appears immediately; the processed RAW replaces it when ready.
    var pendingDiaryImage: UIImage?
    var isEditorPresented = false

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
        // Tapping the viewfinder dismisses the expanded WB list (v3 F3) —
        // before the guard, so it works even if the preview isn't up yet
        isWhiteBalanceExpanded = false
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
        availableLenses = CaptureSession.availableBackLenses()
        hasFrontCamera = CaptureSession.hasFrontCamera()
        captureSession.start()
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
    }

    // Collapsed shows only the active mode; expanded shows the full bank in
    // declaration order. Pure so the decision is unit-testable.
    static func visibleModes(expanded: Bool, selected: WBMode) -> [WBMode] {
        expanded ? WBMode.allCases : [selected]
    }

    func captureForDiary() async {
        guard let photo = await capturePhoto() else { return }
        guard let preview = UIImage(data: photo.jpegData) else {
            errorState?.raise(.captureFailed(reason: "The photo data couldn't be read."))
            return
        }
        pendingDiaryImage = preview
        isEditorPresented = true

        let processed = await processRAWIfPresent(photo, fallback: preview)
        // The user may have saved or retaken while the RAW was developing
        if isEditorPresented {
            pendingDiaryImage = processed
        }
    }

    func captureForPhotobooth() async -> UIImage? {
        guard let photo = await capturePhoto() else { return nil }
        guard let preview = UIImage(data: photo.jpegData) else {
            errorState?.raise(.captureFailed(reason: "The photo data couldn't be read."))
            return nil
        }
        return await processRAWIfPresent(photo, fallback: preview)
    }

    func discardPendingDiaryImage() {
        pendingDiaryImage = nil
        isEditorPresented = false
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
