import Foundation
import Observation
import Photos
import UIKit

/// The diary review step (v4 F10) and its Download (v4 F13): the captured
/// photo in a chosen look, between the shutter and the prompt screen.
///
/// Holds the **original** photo — the JPEG preview, swapped for the
/// developed RAW when it is ready — and only ever renders the look for
/// display or for Download. Nothing here creates a diary entry: OK and
/// Retake go through `CameraViewModel.confirmReview()` / `retake()`.
///
/// v5 F5: the look is a whole `FilmLook` (stock, print, B&W, effect
/// strengths), so the review can offer an Effects tab. The stock-only
/// calls (`stock`, `selectStock`) keep working. The JPEG→RAW swap and the
/// last-wins render are the shared `FilmLookRenderScheduler`.
@Observable
final class DiaryReviewViewModel: Identifiable {
    let id = UUID()
    /// Seeds grain and light leak, so every render of this capture (screen,
    /// re-render, Download) shares one pattern.
    let captureDate: Date
    var errorState: ErrorState?

    /// The original photo: the JPEG preview until the RAW develops.
    private(set) var photo: UIImage
    private(set) var isDevelopingPhoto: Bool
    /// The look chosen on this screen; starts from the camera's stock on
    /// that stock's defaults.
    private(set) var look: FilmLook
    /// The stock of `look`, for the stock chips.
    var stock: StripCustomization.FilmStock { look.stock }
    /// `photo` through `look` at the display size. The original itself for
    /// Off; nil until the first render after `setDisplaySize` lands.
    private(set) var renderedPhoto: UIImage?
    private(set) var isRendering = false
    private(set) var isSavingDownload = false
    /// True for a moment after a successful Download ("Saved").
    private(set) var didSaveDownload = false

    /// The stock row: Off plus the six stocks.
    let stockChoices = StripCustomization.FilmStock.allCases

    /// Disabled while the photo is rendering or saving (spec F13).
    var isDownloadDisabled: Bool { isRendering || isSavingDownload }

    @ObservationIgnored private let scheduler = FilmLookRenderScheduler()
    @ObservationIgnored private var displayPixelSize: CGSize?
    @ObservationIgnored private var savedResetTask: Task<Void, Never>?
    @ObservationIgnored private var lastDownloadedLook: FilmLook?
    @ObservationIgnored private let savePhotoData: @Sendable (Data) async throws -> Void

    /// - Parameters:
    ///   - development: resolves to the developed photo (or the preview if
    ///     there is no RAW). nil when `preview` is already final.
    ///   - savePhotoData: where Download writes; the camera roll, or a stub
    ///     in tests.
    init(
        preview: UIImage,
        stock: StripCustomization.FilmStock,
        captureDate: Date = .now,
        development: Task<UIImage, Never>? = nil,
        savePhotoData: @escaping @Sendable (Data) async throws -> Void = { try await PHPhotoLibrary.saveToCameraRoll(photoData: $0) }
    ) {
        self.photo = preview
        self.look = .stockDefaults(for: stock)
        self.captureDate = captureDate
        self.isDevelopingPhoto = development != nil
        self.savePhotoData = savePhotoData
        if stock == .none { renderedPhoto = preview }

        scheduler.watch(development: development) { [weak self] developed in
            guard let self else { return }
            self.photo = developed
            self.isDevelopingPhoto = false
            // The swap is not a user tap: no debounce
            self.scheduleRender(debounced: false)
        }
    }

    // MARK: Display

    /// The view reports where the photo is drawn. Renders at once on the
    /// first call or a size change.
    func setDisplaySize(_ size: CGSize, scale: CGFloat) {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width >= 1, pixels.height >= 1, pixels != displayPixelSize else { return }
        displayPixelSize = pixels
        scheduleRender(debounced: false)
    }

    // MARK: Look edits (each is debounced: quick taps render only the last)

    /// A stock chip tap. Keeps the effect strengths; drops a print the new
    /// stock can't use.
    func selectStock(_ newStock: StripCustomization.FilmStock) {
        apply(look.with(stock: newStock))
    }

    /// One effect slider (v5 F5), clamped to the slider range.
    func setStrength(_ value: Double, for effect: FilmLook.Effect) {
        var next = look
        next.strengths[effect] = FilmLook.clampedStrength(value)
        apply(next)
    }

    func selectPrint(_ print: StripCustomization.PrintStock?) {
        var next = look
        next.printStock = print
        apply(next)
    }

    func setBlackAndWhite(_ on: Bool) {
        var next = look
        next.blackAndWhite = on
        apply(next)
    }

    /// Back to the current stock on its default print and effects (v5-5).
    func resetToStockDefaults() {
        apply(.stockDefaults(for: look.stock))
    }

    private func apply(_ next: FilmLook) {
        guard next != look else { return }
        look = next
        didSaveDownload = false
        scheduleRender(debounced: true)
    }

    /// Waits for the newest scheduled render, for callers (and tests) that
    /// need the settled result.
    func renderSettled() async {
        await scheduler.settled()
    }

    private func scheduleRender(debounced: Bool) {
        // Off is the original: nothing to render, whatever the size
        guard look.altersPhoto else {
            scheduler.cancelRender()
            renderedPhoto = photo
            isRendering = false
            return
        }
        guard let target = displayPixelSize else { return }
        isRendering = true
        scheduler.schedule(
            photo: photo, look: look, seed: seed, pixelSize: target,
            debounce: debounced ? Constants.Diary.reviewRenderDebounce : nil
        ) { [weak self] outcome in
            guard let self else { return }
            self.isRendering = false
            switch outcome {
            case .rendered(let image):
                self.renderedPhoto = image
            case .failed:
                // The previous look stays on screen; the user can tap again
                self.errorState?.raise(.filmLookRenderFailed)
            }
        }
    }

    private var seed: UInt64 { StripGenerator.photoLookSeed(for: captureDate) }

    // MARK: Download (v4 F13)

    /// Saves this capture in the chosen look — full resolution, HEIC with
    /// the capture's orientation tag — to the camera roll. Waits for the
    /// RAW so the JPEG preview is never what gets saved. Creates no diary
    /// entry.
    // OPEN: v4-15 — repeat Downloads of the same photo and look are allowed;
    // each tap saves one photo (Constants.Diary.blocksRepeatDownload).
    func downloadReview() async {
        guard !isSavingDownload else { return }
        if Constants.Diary.blocksRepeatDownload, lastDownloadedLook == look { return }
        isSavingDownload = true
        didSaveDownload = false
        savedResetTask?.cancel()
        defer { isSavingDownload = false }

        let developed = await developedPhoto()
        let look = look
        let seed = seed
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try ImageProcessor.fullResolutionHEIC(of: developed, look: look, seed: seed)
            }.value
            try await savePhotoData(data)
        } catch let error as AppError {
            errorState?.raise(error)
            return
        } catch {
            errorState?.raise(.saveToLibraryFailed)
            return
        }

        lastDownloadedLook = look
        didSaveDownload = true
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Diary.downloadSavedConfirmationDuration))
            guard !Task.isCancelled else { return }
            self?.didSaveDownload = false
        }
    }

    /// The final original: the developed RAW once it is ready.
    func developedPhoto() async -> UIImage {
        await scheduler.developedPhoto(fallback: photo)
    }

    /// Retake: stop updating. A Download already in flight still finishes.
    func discard() {
        scheduler.cancel()
        savedResetTask?.cancel()
    }
}
