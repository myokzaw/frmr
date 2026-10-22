import Foundation
import Observation
import Photos
import SwiftData
import UIKit

/// The edit step after every Photo-mode shot (v5 F4), and the Roll's
/// re-edit screen (v5 F6) — one view model, two entry points.
///
/// Like the diary review it holds the **original** photo (the JPEG preview,
/// swapped for the developed RAW when ready) and only renders the look for
/// display, Download or the Roll. The JPEG→RAW swap and the last-wins
/// debounced render are the shared `FilmLookRenderScheduler`.
///
/// Endings: `saveToRoll`, `discard`, `retake` and `deleteFromRoll` each
/// finish the session and call `onFinish` once, which dismisses the screen.
/// A fresh capture leaves nothing behind unless it is saved to the Roll;
/// Download writes a photo to the camera roll and creates no Roll record.
@Observable
final class PhotoEditViewModel: Identifiable {
    /// The editor's tools, in tool-bar order: Film, Print, then one per effect.
    enum Tool: Hashable {
        case film
        case print
        case effect(FilmLook.Effect)

        /// Stable identifier (tool bar item, accessibility ids).
        var id: String {
            switch self {
            case .film: return "film"
            case .print: return "print"
            case .effect(let effect): return effect.rawValue
            }
        }

        /// Unknown ids fall back to Film.
        init(id: String) {
            switch id {
            case "film": self = .film
            case "print": self = .print
            default: self = FilmLook.Effect(rawValue: id).map(Tool.effect) ?? .film
            }
        }
    }

    enum Outcome: Equatable {
        case saved
        case discarded
        case retaken
        case deleted
        /// Saved to the Roll, and the diary prompt comes next (v5.1 F4).
        case continuedToDiary
    }

    /// What the diary prompt screen needs once the photo is in the Roll.
    struct DiaryContinuation {
        let rollPhotoID: UUID
        let capturedAt: Date
        /// The developed original (never film-processed).
        let photo: UIImage
        let look: FilmLook
        /// `photo` through `look` at the editor's display size, if rendered.
        let displayImage: UIImage?
    }

    let id = UUID()
    /// Seeds grain and light leak: every render of this photo (screen,
    /// Download, Roll, strips) shares one pattern.
    let captureDate: Date
    var errorState: ErrorState?
    /// Called once when the session ends, to dismiss the screen.
    @ObservationIgnored var onFinish: ((Outcome) -> Void)?

    /// The Roll photo being re-edited; nil for a fresh capture.
    @ObservationIgnored let rollPhoto: RollPhoto?
    var isReEditing: Bool { rollPhoto != nil }

    /// The original photo: the JPEG preview until the RAW develops.
    private(set) var photo: UIImage
    private(set) var isDevelopingPhoto: Bool
    /// The current look; a fresh capture starts from the camera's stock on
    /// that stock's defaults, a re-edit from the saved look.
    private(set) var look: FilmLook
    @ObservationIgnored private let initialLook: FilmLook
    /// `photo` through `look` at the display size; nil until the first
    /// render lands (the original itself for a look that changes nothing).
    private(set) var renderedPhoto: UIImage?
    private(set) var isRendering = false
    /// Hold to compare: true shows the original without the look.
    private(set) var isComparing = false
    var tool: Tool = .film

    private(set) var isSavingDownload = false
    private(set) var didSaveDownload = false
    private(set) var isSavingToRoll = false
    private(set) var outcome: Outcome?
    /// Set when `continueToDiary` succeeded; the camera presents the prompt from it.
    private(set) var diaryContinuation: DiaryContinuation?

    let stockChoices = StripCustomization.FilmStock.allCases
    let effectChoices = FilmLook.Effect.allCases

    @ObservationIgnored private let scheduler = FilmLookRenderScheduler()
    @ObservationIgnored private var displayPixelSize: CGSize?
    @ObservationIgnored private var savedResetTask: Task<Void, Never>?
    @ObservationIgnored private let savePhotoData: @Sendable (Data) async throws -> Void

    /// A fresh Photo-mode capture.
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
        let startLook = FilmLook.stockDefaults(for: stock)
        self.rollPhoto = nil
        self.photo = preview
        self.look = startLook
        self.initialLook = startLook
        self.captureDate = captureDate
        self.isDevelopingPhoto = development != nil
        self.savePhotoData = savePhotoData
        start(development: development)
    }

    /// Re-edit mode, opened from the Roll. The original is the photo's
    /// file (already developed, so there is no swap); nil when it can't be read.
    init?(
        editing rollPhoto: RollPhoto,
        savePhotoData: @escaping @Sendable (Data) async throws -> Void = { try await PHPhotoLibrary.saveToCameraRoll(photoData: $0) }
    ) {
        guard let original = RollViewModel.loadPhoto(for: rollPhoto) else { return nil }
        let startLook = rollPhoto.look
        self.rollPhoto = rollPhoto
        self.photo = original
        self.look = startLook
        self.initialLook = startLook
        self.captureDate = rollPhoto.lookSeedDate
        self.isDevelopingPhoto = false
        self.savePhotoData = savePhotoData
        start(development: nil)
    }

    private func start(development: Task<UIImage, Never>?) {
        if !look.altersPhoto { renderedPhoto = photo }
        scheduler.watch(development: development) { [weak self] developed in
            guard let self else { return }
            self.photo = developed
            self.isDevelopingPhoto = false
            // The swap is not a user edit: no debounce
            self.scheduleRender(debounced: false)
        }
    }

    // MARK: Display

    /// What the photo area shows: the original while comparing, else the
    /// look (the original until the first render lands).
    var displayedPhoto: UIImage {
        isComparing ? photo : (renderedPhoto ?? photo)
    }

    /// The view reports where the photo is drawn (upright points × scale).
    func setDisplaySize(_ size: CGSize, scale: CGFloat) {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width >= 1, pixels.height >= 1, pixels != displayPixelSize else { return }
        displayPixelSize = pixels
        scheduleRender(debounced: false)
    }

    /// Press and hold on the photo. Pure display: no render, no look change.
    func setComparing(_ comparing: Bool) {
        isComparing = comparing
    }

    // MARK: Tool state (what each tab offers)

    /// A print picker only where the stock has a choice (not Off, not slide).
    var isPrintPickerVisible: Bool { look.stock.hasPrintChoice }
    var availablePrints: [StripCustomization.PrintStock] { look.stock.availablePrints }
    /// The print the photo is rendered on; nil for Off.
    var selectedPrint: StripCustomization.PrintStock? { look.resolvedPrint }
    /// A monochrome stock is always B&W: the toggle reads on and is locked.
    var isBlackAndWhiteLocked: Bool { look.stock.isMonochrome }
    var isBlackAndWhiteOn: Bool { look.rendersInBlackAndWhite }
    /// Halation, haze, light leak, grain and vignette need a stock on.
    var areEffectsAvailable: Bool { look.stock.hasEffects }
    /// Reset is meaningful while the look differs from the stock's defaults.
    var canResetToStockDefaults: Bool { !look.isStockDefault }
    /// Whether the look differs from what the session opened with.
    var isModified: Bool { look != initialLook }

    func strength(of effect: FilmLook.Effect) -> Double { look.strengths[effect] }

    // MARK: Look edits (each is debounced: a burst renders once, last wins)

    func selectStock(_ stock: StripCustomization.FilmStock) {
        apply(look.with(stock: stock))
    }

    /// nil = the stock's default print.
    func selectPrint(_ print: StripCustomization.PrintStock?) {
        var next = look
        next.printStock = print
        apply(next)
    }

    func setBlackAndWhite(_ on: Bool) {
        guard !isBlackAndWhiteLocked else { return }
        var next = look
        next.blackAndWhite = on
        apply(next)
    }

    /// One effect slider, clamped to 0…`sliderMaximum` (OPEN: v5-6).
    func setStrength(_ value: Double, for effect: FilmLook.Effect) {
        var next = look
        next.strengths[effect] = FilmLook.clampedStrength(value)
        apply(next)
    }

    /// Back to the current stock on its default print and effects (OPEN: v5-5,
    /// the Effects tab header).
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
            debounce: debounced ? Constants.PhotoEdit.renderDebounce : nil
        ) { [weak self] result in
            guard let self else { return }
            self.isRendering = false
            switch result {
            case .rendered(let image):
                self.renderedPhoto = image
            case .failed:
                // The previous look stays on screen; the user can edit again
                self.errorState?.raise(.filmLookRenderFailed)
            }
        }
    }

    private var seed: UInt64 { StripGenerator.photoLookSeed(for: captureDate) }

    /// The final original: the developed RAW once it is ready.
    func developedPhoto() async -> UIImage {
        await scheduler.developedPhoto(fallback: photo)
    }

    // MARK: Download (writes to the camera roll; no Roll record)

    var isDownloadDisabled: Bool { isRendering || isSavingDownload || isSavingToRoll }

    /// Saves this photo in the current look — full resolution, HEIC with
    /// the capture's orientation tag — to the camera roll. Waits for the
    /// RAW so the JPEG preview is never what gets saved. Stays on the
    /// screen afterwards and creates no Roll record.
    func download() async {
        guard !isSavingDownload else { return }
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

        didSaveDownload = true
        savedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.PhotoEdit.downloadSavedConfirmationDuration))
            guard !Task.isCancelled else { return }
            self?.didSaveDownload = false
        }
    }

    // MARK: Endings

    /// Save to roll. A fresh capture stores the developed original plus the
    /// look as a new Roll photo; a re-edit updates the look on its photo
    /// (never the file). Waits for the RAW. Returns true and finishes the
    /// session on success; on failure raises the error and stays open.
    @discardableResult
    func saveToRoll(context: ModelContext) async -> Bool {
        guard !isSavingToRoll, outcome == nil else { return false }
        isSavingToRoll = true
        defer { isSavingToRoll = false }

        do {
            if let rollPhoto {
                try RollViewModel.update(rollPhoto, look: look, context: context)
            } else {
                let developed = await developedPhoto()
                try RollViewModel.insert(original: developed, look: look, capturedAt: captureDate, context: context)
            }
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
        finish(.saved)
        return true
    }

    /// Continue to diary is offered only right after a capture (v5.1-2).
    var canContinueToDiary: Bool { rollPhoto == nil && outcome == nil && !isSavingToRoll }

    /// Saves to the Roll exactly like Save to roll, then exposes
    /// `diaryContinuation` and finishes with `.continuedToDiary`. Returns
    /// false (and changes nothing) in re-edit or on failure.
    @discardableResult
    func continueToDiary(context: ModelContext) async -> Bool {
        guard canContinueToDiary else { return false }
        isSavingToRoll = true
        defer { isSavingToRoll = false }

        let developed = await developedPhoto()
        let saved: RollPhoto
        do {
            saved = try RollViewModel.insert(original: developed, look: look, capturedAt: captureDate, context: context)
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
        diaryContinuation = DiaryContinuation(
            rollPhotoID: saved.id, capturedAt: captureDate, photo: developed,
            look: look, displayImage: renderedPhoto
        )
        finish(.continuedToDiary)
        return true
    }

    /// Discard: a fresh capture is dropped; a re-edit leaves the Roll
    /// photo exactly as it was.
    func discard() {
        finish(.discarded)
    }

    /// Retake (fresh captures): drop the capture and go back to the camera.
    func retake() {
        finish(.retaken)
    }

    /// For the delete confirmation: entries linked to the photo being re-edited.
    func linkedEntryCount(in context: ModelContext) -> Int {
        rollPhoto.map { RollViewModel.linkedEntryCount(for: $0, in: context) } ?? 0
    }

    /// Delete (re-edit only; the view confirms first): removes the photo's
    /// file and record. Returns true and finishes on success.
    @discardableResult
    func deleteFromRoll(entries: RollViewModel.RollDeletion = .keepEntry, context: ModelContext) -> Bool {
        guard let rollPhoto, outcome == nil else { return false }
        do {
            try RollViewModel.delete(rollPhoto, entries: entries, context: context)
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
        finish(.deleted)
        return true
    }

    private func finish(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        // Stop updating; a Download already in flight still finishes
        scheduler.cancel()
        savedResetTask?.cancel()
        onFinish?(outcome)
    }
}
