import Foundation
import Observation
import Photos
import UIKit

/// The diary review step (v4 F10) and its Download (v4 F13): the captured
/// photo in a chosen stock, between the shutter and the prompt screen.
///
/// Holds the **original** photo — the JPEG preview, swapped for the
/// developed RAW when it is ready — and only ever renders the look for
/// display or for Download. Nothing here creates a diary entry: OK and
/// Retake go through `CameraViewModel.confirmReview()` / `retake()`.
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
    /// The stock chosen on this screen; starts from the camera's.
    private(set) var stock: StripCustomization.FilmStock
    /// `photo` through `stock` at the display size. The original itself for
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

    @ObservationIgnored private var development: Task<UIImage, Never>?
    @ObservationIgnored private var developmentWatch: Task<Void, Never>?
    @ObservationIgnored private var displayPixelSize: CGSize?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var renderGeneration = 0
    @ObservationIgnored private var savedResetTask: Task<Void, Never>?
    @ObservationIgnored private var lastDownloadedStock: StripCustomization.FilmStock?
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
        self.stock = stock
        self.captureDate = captureDate
        self.development = development
        self.isDevelopingPhoto = development != nil
        self.savePhotoData = savePhotoData
        if stock == .none { renderedPhoto = preview }

        if let development {
            developmentWatch = Task { [weak self] in
                let developed = await development.value
                guard let self, !Task.isCancelled else { return }
                self.photo = developed
                self.isDevelopingPhoto = false
                // The swap is not a user tap: no debounce
                self.scheduleRender(debounced: false)
            }
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

    /// A stock chip tap. Debounced: quick taps render only the last stock.
    func selectStock(_ newStock: StripCustomization.FilmStock) {
        guard newStock != stock else { return }
        stock = newStock
        didSaveDownload = false
        scheduleRender(debounced: true)
    }

    /// Waits for the newest scheduled render, for callers (and tests) that
    /// need the settled result.
    func renderSettled() async {
        while let task = renderTask {
            await task.value
            // Superseded tasks hand over to their successor; a finished
            // newest task clears itself
            if renderTask == task { return }
        }
    }

    // Last request wins: every call bumps the generation, cancels the
    // previous task, and only the newest generation publishes its result.
    private func scheduleRender(debounced: Bool) {
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        let photo = photo
        let stock = stock

        guard stock != .none else {
            // Off is the original: nothing to render
            renderTask = nil
            renderedPhoto = photo
            isRendering = false
            return
        }
        guard let target = displayPixelSize else { return }
        isRendering = true
        let seed = seed

        renderTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: .seconds(Constants.Diary.reviewRenderDebounce))
                guard !Task.isCancelled else { return }
            }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageProcessor.renderFullLook(of: photo, stock: stock, seed: seed, coveringPixelSize: target) }
            }.value
            guard let self, generation == self.renderGeneration else { return }
            self.renderTask = nil
            self.isRendering = false
            switch result {
            case .success(let image):
                self.renderedPhoto = image
            case .failure:
                // The previous look stays on screen; the user can tap again
                self.errorState?.raise(.filmLookRenderFailed)
            }
        }
    }

    private var seed: UInt64 { StripGenerator.photoLookSeed(for: captureDate) }

    // MARK: Download (v4 F13)

    /// Saves this capture in the chosen stock — full resolution, the
    /// stock's default print and effects, HEIC with the capture's
    /// orientation tag — to the camera roll. Waits for the RAW so the JPEG
    /// preview is never what gets saved. Creates no diary entry.
    // OPEN: v4-15 — repeat Downloads of the same photo and stock are allowed;
    // each tap saves one photo (Constants.Diary.blocksRepeatDownload).
    func downloadReview() async {
        guard !isSavingDownload else { return }
        if Constants.Diary.blocksRepeatDownload, lastDownloadedStock == stock { return }
        isSavingDownload = true
        didSaveDownload = false
        savedResetTask?.cancel()
        defer { isSavingDownload = false }

        let developed = await developedPhoto()
        let stock = stock
        let seed = seed
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let look = try ImageProcessor.renderFullLook(of: developed, stock: stock, seed: seed)
                return try ImageProcessor.heicData(from: look)
            }.value
            try await savePhotoData(data)
        } catch let error as AppError {
            errorState?.raise(error)
            return
        } catch {
            errorState?.raise(.saveToLibraryFailed)
            return
        }

        lastDownloadedStock = stock
        didSaveDownload = true
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.Diary.downloadSavedConfirmationDuration))
            guard !Task.isCancelled else { return }
            self?.didSaveDownload = false
        }
    }

    /// The final original: the developed RAW once it is ready.
    func developedPhoto() async -> UIImage {
        guard let development else { return photo }
        return await development.value
    }

    /// Retake: stop updating. A Download already in flight still finishes.
    func discard() {
        developmentWatch?.cancel()
        renderTask?.cancel()
        renderTask = nil
        savedResetTask?.cancel()
    }
}
