import AVFoundation
import Foundation

nonisolated struct CapturedPhoto: Sendable {
    let jpegData: Data
    let rawData: Data?
}

nonisolated enum CameraPosition: Sendable {
    case back
    case front

    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }
}

// Back-camera lens options; the front camera always uses its wide lens
nonisolated enum CameraLens: String, CaseIterable, Identifiable, Sendable {
    case ultraWide
    case wide
    case telephoto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ultraWide: return "0.5×"
        case .wide: return "1×"
        case .telephoto: return "Tele"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
}

// All AVFoundation session work lives here, off the main actor. Session
// mutation happens on a dedicated serial queue; teardown must never run on
// the main thread (project.md §9).
// @unchecked Sendable: all mutable state is confined to sessionQueue.
nonisolated final class CaptureSession: @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "frmr.captureSession")
    private let photoOutput = AVCapturePhotoOutput()
    private var camera: AVCaptureDevice?
    private var isConfigured = false
    // Gravity-driven source of the capture rotation angle. The interface is
    // locked to portrait so the connection would otherwise tag every photo as
    // portrait, saving a landscape-held shot with the world lying on its side.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    // Capture delegates must stay retained until their capture finishes
    private var activeCaptures: [Int64: PhotoCaptureDelegate] = [:]
    // Retained only while a tap-triggered autofocus is settling (v2 F1)
    private var focusObservation: NSKeyValueObservation?

    static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // Which back lenses this device actually has (discovery is thread-safe)
    static func availableBackLenses() -> [CameraLens] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: CameraLens.allCases.map(\.deviceType),
            mediaType: .video,
            position: .back
        )
        let foundTypes = Set(discovery.devices.map(\.deviceType))
        return CameraLens.allCases.filter { foundTypes.contains($0.deviceType) }
    }

    static func hasFrontCamera() -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    func switchCamera(to position: CameraPosition, lens: CameraLens) {
        sessionQueue.async {
            let deviceType: AVCaptureDevice.DeviceType =
                position == .front ? .builtInWideAngleCamera : lens.deviceType
            guard
                let device = AVCaptureDevice.default(deviceType, for: .video, position: position.avPosition),
                let input = try? AVCaptureDeviceInput(device: device)
            else {
                // Safe to continue: the requested camera doesn't exist on this
                // device, the current one stays active and visible in the viewfinder
                print("[CaptureSession] Requested camera unavailable: \(position)/\(lens)")
                return
            }

            let previousInputs = self.session.inputs
            self.session.beginConfiguration()
            previousInputs.forEach { self.session.removeInput($0) }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.camera = device
                self.makeRotationCoordinator(for: device)
            } else {
                // Restore the previous camera so capture keeps working
                previousInputs
                    .filter { self.session.canAddInput($0) }
                    .forEach { self.session.addInput($0) }
                print("[CaptureSession] Could not attach \(position)/\(lens); keeping previous camera")
            }
            self.session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async {
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.camera != nil else {
                    continuation.resume(throwing: AppError.captureFailed(reason: "No camera is available on this device."))
                    return
                }
                self.applyCaptureRotation()
                let settings = self.makePhotoSettings()
                let delegate = PhotoCaptureDelegate(continuation: continuation) { [weak self] id in
                    self?.sessionQueue.async {
                        self?.activeCaptures[id] = nil
                    }
                }
                self.activeCaptures[settings.uniqueID] = delegate
                self.photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// Tags the next capture with the angle that makes it horizon-level.
    ///
    /// The preview deliberately never rotates (a rotating preview shifts the
    /// crop the user is composing under them), so the connection's angle is
    /// the only thing that records how the phone was actually held. The
    /// coordinator reads gravity rather than `UIDevice.orientation`, so a
    /// phone held at an angle resolves to the nearest upright quarter-turn
    /// instead of whatever cardinal orientation the device last reported.
    ///
    /// `AVCapturePhotoOutput` applies this as an EXIF tag rather than by
    /// rotating buffers, so setting it per-capture costs nothing.
    private func applyCaptureRotation() {
        guard let connection = photoOutput.connection(with: .video),
              let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture
        else {
            return
        }
        // Setting an unsupported angle raises NSInvalidArgumentException,
        // which Swift cannot catch — the guard is what keeps it a no-op
        // instead of a crash on hardware that reports a narrower set.
        guard connection.isVideoRotationAngleSupported(angle) else {
            print("[CaptureSession] Capture rotation \(angle)° unsupported; leaving connection as-is")
            return
        }
        connection.videoRotationAngle = angle
    }

    // The coordinator holds a weak reference to its device, so it is rebuilt
    // whenever the active camera changes rather than outliving it.
    private func makeRotationCoordinator(for device: AVCaptureDevice) {
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    func apply(whiteBalance mode: WBMode) {
        sessionQueue.async {
            guard let camera = self.camera else { return }
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }

                if let preset = mode.temperatureAndTint {
                    if camera.isWhiteBalanceModeSupported(.locked) {
                        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                            temperature: preset.temperature,
                            tint: preset.tint
                        )
                        let gains = self.clampedGains(camera.deviceWhiteBalanceGains(for: values), for: camera)
                        camera.setWhiteBalanceModeLocked(with: gains)
                    }
                } else if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    camera.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } catch {
                // Safe to continue: a failed lock leaves the previous white balance
                // active, which is directly visible in the viewfinder. No data is lost.
                print("[CaptureSession] Could not set white balance: \(error)")
            }
        }
    }

    // MARK: Manual controls (v2 F1–F3)

    /// Points the focus and exposure metering at a device-space point (already
    /// normalised 0–1 by the preview layer). Unsupported on some cameras — the
    /// front camera in particular — where it silently stays centre-weighted.
    func setFocusAndExposure(atDevicePoint point: CGPoint) {
        sessionQueue.async {
            guard let camera = self.camera else { return }
            guard camera.isFocusPointOfInterestSupported || camera.isExposurePointOfInterestSupported else {
                return
            }
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }

                if camera.isFocusPointOfInterestSupported, camera.isFocusModeSupported(.autoFocus) {
                    camera.focusPointOfInterest = point
                    camera.focusMode = .autoFocus
                }
                if camera.isExposurePointOfInterestSupported, camera.isExposureModeSupported(.autoExpose) {
                    camera.exposurePointOfInterest = point
                    camera.exposureMode = .autoExpose
                }
            } catch {
                // Safe to continue: focus stays wherever it was, which the user
                // can see in the viewfinder. Retrying is a second tap.
                print("[CaptureSession] Could not set focus/exposure point: \(error)")
                return
            }
            self.observeFocusSettling(on: camera)
        }
    }

    /// Fires a light haptic the moment autofocus stops hunting, so the lock is
    /// felt as well as seen.
    // OPEN: v2-1 — whether to drop to .locked once focus settles is undecided;
    // Constants.Camera.lockFocusAfterTap is false (stay continuous) for now.
    private func observeFocusSettling(on camera: AVCaptureDevice) {
        focusObservation = camera.observe(\.isAdjustingFocus, options: [.new]) { [weak self] device, change in
            guard change.newValue == false else { return }
            self?.sessionQueue.async {
                self?.focusObservation = nil
                guard Constants.Camera.lockFocusAfterTap,
                      device.isFocusModeSupported(.locked)
                else {
                    return
                }
                if (try? device.lockForConfiguration()) != nil {
                    device.focusMode = .locked
                    device.unlockForConfiguration()
                }
            }
            Task { @MainActor in Haptics.focusLocked() }
        }

        // If the device never reports settling, stop holding the observer
        sessionQueue.asyncAfter(deadline: .now() + Constants.Camera.focusSettleDuration) { [weak self] in
            self?.focusObservation = nil
        }
    }

    /// Exposure compensation in stops. Clamped to what the device reports it
    /// can do, which is narrower than our own range on some hardware.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async {
            guard let camera = self.camera else { return }
            let clamped = min(max(ev, camera.minExposureTargetBias), camera.maxExposureTargetBias)
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }
                camera.setExposureTargetBias(clamped)
            } catch {
                // Safe to continue: the previous bias stays applied and visible
                print("[CaptureSession] Could not set exposure bias: \(error)")
            }
        }
    }

    /// The zoom range this camera actually offers, capped by our soft maximum
    /// (devices go further, but image quality falls off).
    func zoomRange() async -> ClosedRange<CGFloat> {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard let camera = self.camera else {
                    continuation.resume(returning: Constants.Camera.minZoomFactor...Constants.Camera.minZoomFactor)
                    return
                }
                let lower = camera.minAvailableVideoZoomFactor
                let upper = max(lower, min(camera.maxAvailableVideoZoomFactor, Constants.Camera.maxZoomFactor))
                continuation.resume(returning: lower...upper)
            }
        }
    }

    func setZoom(_ factor: CGFloat, animated: Bool) {
        sessionQueue.async {
            guard let camera = self.camera else { return }
            let clamped = Self.clampedZoom(
                factor,
                min: camera.minAvailableVideoZoomFactor,
                max: min(camera.maxAvailableVideoZoomFactor, Constants.Camera.maxZoomFactor)
            )
            do {
                try camera.lockForConfiguration()
                defer { camera.unlockForConfiguration() }
                if animated {
                    camera.ramp(toVideoZoomFactor: clamped, withRate: Constants.Camera.zoomRampRate)
                } else {
                    camera.videoZoomFactor = clamped
                }
            } catch {
                // Safe to continue: the current zoom level stays as-is
                print("[CaptureSession] Could not set zoom: \(error)")
            }
        }
    }

    // Pure, so the clamping is unit-testable without a device
    static func clampedZoom(_ factor: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard upper > lower else { return lower }
        return Swift.min(Swift.max(factor, lower), upper)
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else {
            // No back camera (e.g. simulator). capturePhoto() reports this to the
            // user as a captureFailed error; the viewfinder simply stays dark.
            return
        }

        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        camera = device
        makeRotationCoordinator(for: device)
    }

    // RAW + processed pair where supported; processed-only otherwise (project.md §9).
    // AVVideoQualityKey must live inside AVVideoCompressionPropertiesKey — the
    // RAW initializer throws NSInvalidArgumentException if it's top-level.
    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let processedFormat: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.jpeg,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: NSNumber(value: Constants.jpegCompressionQuality)
            ]
        ]
        if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
            return AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: processedFormat)
        }
        return AVCapturePhotoSettings(format: processedFormat)
    }

    private func clampedGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        for camera: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        var clamped = gains
        clamped.redGain = min(max(clamped.redGain, 1), camera.maxWhiteBalanceGain)
        clamped.greenGain = min(max(clamped.greenGain, 1), camera.maxWhiteBalanceGain)
        clamped.blueGain = min(max(clamped.blueGain, 1), camera.maxWhiteBalanceGain)
        return clamped
    }
}

private nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<CapturedPhoto, Error>
    private let onFinish: (Int64) -> Void
    private var jpegData: Data?
    private var rawData: Data?
    private var processingError: Error?

    init(continuation: CheckedContinuation<CapturedPhoto, Error>, onFinish: @escaping (Int64) -> Void) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            processingError = error
            return
        }
        if photo.isRawPhoto {
            rawData = photo.fileDataRepresentation()
        } else {
            jpegData = photo.fileDataRepresentation()
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        defer { onFinish(resolvedSettings.uniqueID) }

        if let error = processingError ?? error {
            continuation.resume(throwing: AppError.captureFailed(reason: error.localizedDescription))
            return
        }
        guard let jpegData else {
            continuation.resume(throwing: AppError.captureFailed(reason: "The camera returned no image data."))
            return
        }
        continuation.resume(returning: CapturedPhoto(jpegData: jpegData, rawData: rawData))
    }
}
