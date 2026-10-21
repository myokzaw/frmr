import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalKit
import UIKit

// v4 F9 live film preview: camera frames through the stock's film cube
// (colour and tone only — no grain, halation, bloom or leak), drawn into an
// MTKView with one Metal-backed CIContext.
//
// Tap-to-focus decision: the existing AVCaptureVideoPreviewLayer stays
// underneath this view, same frame, and keeps doing the tap → device point
// conversion (`captureDevicePointConverted`, proven since v2). This view
// draws the frame with the same aspect-fill geometry as that layer
// (`aspectFillRect`, unit-tested against AVFoundation's own fit math), so
// what the user taps is where the layer says it is. With stock Off the
// view is paused and hidden and the plain layer is the viewfinder.

/// Receives frames on the capture session's video queue and keeps only the
/// newest one; the renderer picks it up on its next draw.
nonisolated final class FilmPreviewFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var sequence: UInt64 = 0

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.withLock {
            latest = pixelBuffer
            sequence &+= 1
        }
    }

    /// The newest frame and its sequence number, nil before the first.
    func newestFrame() -> (buffer: CVPixelBuffer, sequence: UInt64)? {
        lock.withLock { latest.map { ($0, sequence) } }
    }
}

/// Owns the Metal device, the CIContext and the current stock's cube, and
/// draws into every `FilmPreviewView` it backs.
final class FilmPreviewRenderer: NSObject, MTKViewDelegate {
    /// Hand this to `CaptureSession.setVideoFrameDelegate(_:)`.
    let frameSink = FilmPreviewFrameSink()

    let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let context: CIContext?
    private let outputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private var cube: Data?
    private var stock: StripCustomization.FilmStock = .none
    private var cubeGeneration = 0
    private var lastDrawnSequence: UInt64?
    private var views: [WeakView] = []

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        commandQueue = device?.makeCommandQueue()
        // One context for the life of the camera: building one per frame
        // costs more than the frame
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        if device == nil {
            print("[FilmPreviewRenderer] No Metal device; the plain preview layer stays the viewfinder")
        }
        super.init()
    }

    /// Off pauses drawing; a stock builds (or fetches) its cube off the
    /// main actor and the next frame uses it. Last call wins.
    func setStock(_ newStock: StripCustomization.FilmStock) {
        stock = newStock
        cubeGeneration += 1
        let generation = cubeGeneration
        updatePaused()
        guard newStock != .none else {
            cube = nil
            return
        }
        Task { [weak self] in
            let cube = await Task.detached(priority: .userInitiated) { Self.previewCube(for: newStock) }.value
            guard let self, generation == self.cubeGeneration else { return }
            self.cube = cube
            self.lastDrawnSequence = nil
        }
    }

    var isActive: Bool { stock != .none }

    func attach(_ view: MTKView) {
        views.removeAll { $0.view == nil }
        views.append(WeakView(view: view))
        view.device = device
        view.delegate = self
        view.isPaused = !isActive
    }

    private func updatePaused() {
        views.removeAll { $0.view == nil }
        for entry in views { entry.view?.isPaused = !isActive }
    }

    // MARK: Pure pieces (unit-tested)

    /// The same cube the strip uses for this stock on its default print
    /// (FilmLUT's cache), so the viewfinder and the saved look agree on
    /// colour and tone. nil for Off.
    nonisolated static func previewCube(for stock: StripCustomization.FilmStock) -> Data? {
        guard let negative = stock.negative, let print = stock.defaultPrint?.profile else { return nil }
        return FilmLUT.cachedCube(negative: negative, print: print, monochrome: stock.isMonochrome)
    }

    /// Where a frame of `imageSize` lands in a view of `bounds` under
    /// aspect fill — identical to `AVLayerVideoGravity.resizeAspectFill`:
    /// scaled uniformly to cover, centred, overflow cropped.
    nonisolated static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// One frame, ready to render into a `drawableSize` target whose origin
    /// is top-left: aspect-filled, then (for a stock) through the cube. The
    /// scale comes first so the cube only runs on displayed pixels.
    nonisolated static func previewImage(_ frame: CIImage, cube: Data?, drawableSize: CGSize) -> CIImage {
        let extent = frame.extent
        let target = aspectFillRect(imageSize: extent.size, in: CGRect(origin: .zero, size: drawableSize))
        let scale = target.width / max(extent.width, 1)
        var image = frame
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: target.minX, y: target.minY))
        if let cube {
            let filter = CIFilter.colorCubeWithColorSpace()
            filter.inputImage = image
            filter.cubeDimension = Float(Constants.ImageProcessing.Film.lutDimension)
            filter.cubeData = cube
            filter.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            image = filter.outputImage ?? image
        }
        return image.cropped(to: CGRect(origin: .zero, size: drawableSize))
    }

    /// Renders `image` into `texture` with `y` running down, as a screen
    /// expects. Core Image's own origin is bottom-left, so the destination
    /// is flipped. Internal so the orientation is testable offscreen.
    func render(_ image: CIImage, to texture: MTLTexture, commandBuffer: MTLCommandBuffer) throws {
        guard let context else { return }
        let destination = CIRenderDestination(mtlTexture: texture, commandBuffer: commandBuffer)
        destination.isFlipped = true
        destination.colorSpace = outputColorSpace
        _ = try context.startTask(toRender: image, to: destination)
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastDrawnSequence = nil
    }

    func draw(in view: MTKView) {
        guard isActive, let commandQueue, let frame = frameSink.newestFrame() else { return }
        // No new camera frame since the last draw: the screen already shows it
        guard frame.sequence != lastDrawnSequence else { return }
        guard
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }
        let image = Self.previewImage(
            CIImage(cvPixelBuffer: frame.buffer), cube: cube, drawableSize: view.drawableSize
        )
        do {
            try render(image, to: drawable.texture, commandBuffer: commandBuffer)
        } catch {
            // Safe to continue: one dropped preview frame, the next replaces it
            print("[FilmPreviewRenderer] Frame render failed: \(error)")
            return
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        lastDrawnSequence = frame.sequence
    }

    private struct WeakView {
        weak var view: MTKView?
    }
}

/// The live film viewfinder (UIKit). Frontend embeds it with a
/// UIViewRepresentable laid exactly over the existing preview layer view;
/// it ignores touches, so taps, pinches and drags reach the gestures
/// underneath unchanged.
final class FilmPreviewView: UIView {
    let metalView = MTKView()

    init(renderer: FilmPreviewRenderer) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        metalView.translatesAutoresizingMaskIntoConstraints = false
        // Core Image writes the drawable's texture directly
        metalView.framebufferOnly = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.preferredFramesPerSecond = Constants.Camera.filmPreviewFramesPerSecond
        metalView.isOpaque = true
        metalView.autoResizeDrawable = true
        addSubview(metalView)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            metalView.topAnchor.constraint(equalTo: topAnchor),
            metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        renderer.attach(metalView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
