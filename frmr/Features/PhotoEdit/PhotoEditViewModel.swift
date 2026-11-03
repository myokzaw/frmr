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
    /// The editor's tools, in tool-bar order: Exposure (v5.2), Shadows,
    /// Highlights (F-122-C), Contrast, Saturation (F-122-J), Crop (F-122-F),
    /// Film, Print, then one per effect (`allTools`).
    enum Tool: Hashable {
        case exposure
        case shadows
        case highlights
        case contrast
        case saturation
        case crop
        case film
        case print
        case effect(FilmLook.Effect)

        /// Every tool in tool-bar order.
        static var allTools: [Tool] {
            [.exposure, .shadows, .highlights, .contrast, .saturation, .crop, .film, .print] + FilmLook.Effect.allCases.map(Tool.effect)
        }

        /// Stable identifier (tool bar item, accessibility ids).
        var id: String {
            switch self {
            case .exposure: return "exposure"
            case .shadows: return "shadows"
            case .highlights: return "highlights"
            case .contrast: return "contrast"
            case .saturation: return "saturation"
            case .crop: return "crop"
            case .film: return "film"
            case .print: return "print"
            case .effect(let effect): return effect.rawValue
            }
        }

        /// Unknown ids fall back to Film.
        init(id: String) {
            switch id {
            case "exposure": self = .exposure
            case "shadows": self = .shadows
            case "highlights": self = .highlights
            case "contrast": self = .contrast
            case "saturation": self = .saturation
            case "crop": self = .crop
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
        /// Gallery import: this pick was skipped (nothing saved).
        case skipped
        /// Gallery import: saved, and the rest of the batch gets this look.
        case appliedToRest
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

    /// Gallery import (F-122-E): "2 of 5" while this editor is one pick of a
    /// batch; nil otherwise.
    let importCounter: String?
    /// Whether a pick follows this one (Apply to rest needs one).
    let importHasRemaining: Bool
    var isImporting: Bool { importCounter != nil }
    /// Shows the "Imported" mark: an import in progress, or a saved import.
    var isImportedPhoto: Bool { isImporting || rollPhoto?.source == .imported }
    private var newPhotoSource: RollPhoto.Source { isImporting ? .imported : .camera }

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
    /// The look `renderedPhoto` was rendered with.
    @ObservationIgnored private var renderedLook: FilmLook?
    /// Shown instead of `renderedPhoto` while a render for a new crop or turn
    /// is pending: the right geometry, without (or with the previous) film,
    /// so the old framing never flashes (F-122-F).
    private var standIn: UIImage?
    /// Bumps each time a render replaces a stand-in, so the view can
    /// cross-fade exactly that swap.
    private(set) var standInSwaps = 0
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

    // MARK: Previews (v5.2 M5)

    /// THIS photo in each stock (the current look otherwise); filled by
    /// `requestPreviews`. Empty until the first request lands.
    private(set) var stockPreviews: [StripCustomization.FilmStock: UIImage] = [:]
    /// THIS photo on each print the current stock offers.
    private(set) var printPreviews: [StripCustomization.PrintStock: UIImage] = [:]
    /// How many preview batches have been rendered (cache misses); for tests.
    @ObservationIgnored private(set) var previewRenderCount = 0
    /// Bumps when the developed RAW replaces the JPEG, so previews of the
    /// preview are never served for the real photo.
    @ObservationIgnored private var photoGeneration = 0
    @ObservationIgnored private var stockCache: [PreviewKey: [StripCustomization.FilmStock: UIImage]] = [:]
    @ObservationIgnored private var printCache: [PreviewKey: [StripCustomization.PrintStock: UIImage]] = [:]
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    /// What a preview set depends on: the photo (by generation), the look
    /// with the dimension being previewed factored out, and the size.
    private struct PreviewKey: Hashable {
        let generation: Int
        let look: FilmLook
        let width: Int
        let height: Int
    }

    @ObservationIgnored private let scheduler = FilmLookRenderScheduler()
    @ObservationIgnored private var displayPixelSize: CGSize?
    @ObservationIgnored private var savedResetTask: Task<Void, Never>?
    @ObservationIgnored private let savePhotoData: @Sendable (Data) async throws -> Void

    /// A fresh Photo-mode capture.
    /// - Parameters:
    ///   - development: resolves to the developed photo (or the preview if
    ///     there is no RAW). nil when `preview` is already final.
    ///   - crop: the digital zoom's centred crop (F-122-G); nil at 1x.
    ///   - savePhotoData: where Download writes; the camera roll, or a stub
    ///     in tests.
    init(
        preview: UIImage,
        stock: StripCustomization.FilmStock,
        captureDate: Date = .now,
        development: Task<UIImage, Never>? = nil,
        crop: CropRect? = nil,
        savePhotoData: @escaping @Sendable (Data) async throws -> Void = { try await PHPhotoLibrary.saveToCameraRoll(photoData: $0) }
    ) {
        let startLook = FilmLook.stockDefaults(for: stock).with(crop: crop)
        self.rollPhoto = nil
        self.importCounter = nil
        self.importHasRemaining = false
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
        // F-122-B: the editor shows the current model. The stored look stays
        // at its old version until Save; Discard never touches it. The upgrade
        // is not a user edit, so it is also the baseline for `isModified`.
        let startLook = rollPhoto.look.with(modelVersion: Constants.ImageProcessing.Film.currentModelVersion)
        self.rollPhoto = rollPhoto
        self.importCounter = nil
        self.importHasRemaining = false
        self.photo = original
        self.look = startLook
        self.initialLook = startLook
        self.captureDate = rollPhoto.lookSeedDate
        self.isDevelopingPhoto = false
        self.savePhotoData = savePhotoData
        start(development: nil)
    }

    /// One pick of a gallery import (F-122-E): already developed, the look
    /// Off at the current film model, dated now (`importedAt`).
    init(
        importing photo: UIImage,
        importedAt: Date,
        counterText: String,
        hasRemaining: Bool,
        savePhotoData: @escaping @Sendable (Data) async throws -> Void = { try await PHPhotoLibrary.saveToCameraRoll(photoData: $0) }
    ) {
        let startLook = FilmLook.stockDefaults(for: .none).with(modelVersion: Constants.ImageProcessing.Film.currentModelVersion)
        self.rollPhoto = nil
        self.importCounter = counterText
        self.importHasRemaining = hasRemaining
        self.photo = photo
        self.look = startLook
        self.initialLook = startLook
        self.captureDate = importedAt
        self.isDevelopingPhoto = false
        self.savePhotoData = savePhotoData
        start(development: nil)
    }

    private func start(development: Task<UIImage, Never>?) {
        if !renderLook.altersOutput { renderedPhoto = photo }
        scheduler.watch(development: development) { [weak self] developed in
            guard let self else { return }
            self.photo = developed
            self.photoGeneration += 1
            self.isDevelopingPhoto = false
            // The swap is not a user edit: no debounce
            self.scheduleRender(debounced: false)
        }
    }

    // MARK: Display

    /// What the photo area shows: the turned, plain photo while cropping (the
    /// frame sits over it), the plain photo with the crop and turn while
    /// comparing, else the look (a stand-in with the right framing until the
    /// first render for it lands).
    var displayedPhoto: UIImage {
        if isCropping { return cropCanvasPhoto }
        if isComparing { return ImageProcessor.geometryOnly(photo, look: look) }
        return standIn ?? renderedPhoto ?? photo
    }

    /// The whole photo, turned, for the crop canvas.
    var cropCanvasPhoto: UIImage { ImageProcessor.turnedPhoto(photo, quarterTurns: look.quarterTurns) }

    /// The view reports where the photo is drawn (upright points × scale).
    func setDisplaySize(_ size: CGSize, scale: CGFloat) {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width >= 1, pixels.height >= 1, pixels != displayPixelSize else { return }
        displayPixelSize = pixels
        scheduleRender(debounced: false)
    }

    /// Press and hold on the photo. Pure display: no render, no look change.
    func setComparing(_ comparing: Bool) {
        // The Crop tool already shows the plain photo
        isComparing = comparing && !isCropping
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

    // MARK: Exposure (v5.2 F-EXP)

    var exposure: Double { look.exposure }

    /// "+0.3 EV", "0 EV", "−1.0 EV" (a true minus sign).
    var exposureReadout: String { Self.exposureReadout(for: look.exposure) }

    static func exposureReadout(for exposure: Double) -> String {
        let value = FilmLook.snappedExposure(exposure)
        guard value != 0 else { return "0 EV" }
        let magnitude = String(format: "%.1f", abs(value))
        return (value > 0 ? "+" : "\u{2212}") + magnitude + " EV"
    }

    /// Sets the exposure, snapped to ⅓ stop and clamped to ±2 EV.
    func setExposure(_ value: Double) {
        var next = look
        next.exposure = FilmLook.snappedExposure(value)
        apply(next)
    }

    // MARK: Shadows, Highlights, Contrast and Saturation (F-122-C, F-122-J)

    var contrast: Double { look.contrast }
    var saturation: Double { look.saturation }
    var contrastReadout: String { Self.toneReadout(for: look.contrast) }
    var saturationReadout: String { Self.toneReadout(for: look.saturation) }
    var shadows: Double { look.shadows }
    var highlights: Double { look.highlights }
    var shadowsReadout: String { Self.toneReadout(for: look.shadows) }
    var highlightsReadout: String { Self.toneReadout(for: look.highlights) }

    /// "+25", "−40" (a true minus sign), "0".
    static func toneReadout(for value: Double) -> String {
        let snapped = FilmLook.snappedTone(value)
        guard snapped != 0 else { return "0" }
        return (snapped > 0 ? "+" : "\u{2212}") + String(Int(abs(snapped)))
    }

    /// Sets Shadows, snapped to whole steps and clamped to ±100.
    func setShadows(_ value: Double) {
        var next = look
        next.shadows = FilmLook.snappedTone(value)
        apply(next)
    }

    /// Sets Highlights, snapped to whole steps and clamped to ±100.
    func setHighlights(_ value: Double) {
        var next = look
        next.highlights = FilmLook.snappedTone(value)
        apply(next)
    }

    /// Sets Contrast, snapped to whole steps and clamped to ±100.
    func setContrast(_ value: Double) {
        var next = look
        next.contrast = FilmLook.snappedTone(value)
        apply(next)
    }

    /// Sets Saturation, snapped to whole steps and clamped to ±100.
    func setSaturation(_ value: Double) {
        var next = look
        next.saturation = FilmLook.snappedTone(value)
        apply(next)
    }

    // MARK: Crop (F-122-F)

    /// Whether the Crop tool is open.
    var isCropping: Bool { tool == .crop }

    /// Chooses a tool. Opening or leaving Crop swaps what the photo area
    /// shows (the whole photo with the frame, or the cropped result), so
    /// that re-renders.
    func select(tool next: Tool) {
        let crossesCrop = (tool == .crop) != (next == .crop)
        tool = next
        if crossesCrop { scheduleRender(debounced: false) }
    }

    /// The crop being edited: the stored one, else the whole photo (in the
    /// photo's own orientation, which an Original frame is measured against).
    var cropState: CropRect {
        look.crop ?? CropRect(
            rect: CGRect(x: 0, y: 0, width: 1, height: 1), preset: .original,
            isLandscape: CropGeometry.defaultIsLandscape(for: cropImageSize)
        )
    }
    /// Back to the whole photo is meaningful while a crop is stored or the
    /// photo is turned.
    var canResetCrop: Bool { look.crop != nil || look.quarterTurns != 0 }
    /// Every preset but a square, and not Original on a square photo.
    var canSwapCropOrientation: Bool {
        guard cropState.preset.canSwapOrientation else { return false }
        return cropState.preset != .original || cropImageSize.width != cropImageSize.height
    }
    /// "Original", "3:4"… while a crop is active; empty otherwise (the tool
    /// bar's VoiceOver value).
    var cropReadout: String { look.hasActiveCrop ? cropState.preset.label : "" }

    /// The turned photo's size in pixels: the geometry's reference (the crop
    /// is relative to the photo as turned).
    private var cropImageSize: CGSize {
        let turned = cropCanvasPhoto
        return CGSize(width: turned.size.width * turned.scale, height: turned.size.height * turned.scale)
    }

    private func cropRatio(for crop: CropRect) -> CGFloat? {
        CropGeometry.ratio(for: crop.preset, isLandscape: crop.isLandscape, imageSize: cropImageSize)
    }

    /// Picks a preset: a fixed ratio is fitted into the photo, centred, in
    /// the photo's own orientation; Original is the whole photo; Free keeps
    /// the frame as it is.
    func selectCropPreset(_ preset: CropPreset) {
        let landscape = CropGeometry.defaultIsLandscape(for: cropImageSize)
        let rect = preset == .free
            ? cropState.rect
            : CropGeometry.fit(preset, isLandscape: landscape, in: cropImageSize)
        setCrop(CropRect(rect: rect, preset: preset, isLandscape: landscape))
    }

    /// Portrait ↔ landscape, about the frame's centre, same area, shrunk to
    /// fit. Original stays Original (the largest centred frame of the photo's
    /// ratio inverted, `isLandscape` flipped) and Free swaps its own width and height.
    func swapCropOrientation() {
        guard canSwapCropOrientation else { return }
        let crop = cropState
        // The rect, not the flag, says which way an Original or Free frame points
        let pixels = CGSize(width: crop.width * cropImageSize.width, height: crop.height * cropImageSize.height)
        let landscape = crop.preset == .original || crop.preset == .free ? pixels.width <= pixels.height : !crop.isLandscape
        // Original is always the largest centred frame, so swapping back restores the whole photo
        let rect = crop.preset == .original
            ? CropGeometry.fit(.original, isLandscape: landscape, in: cropImageSize)
            : CropGeometry.swapped(crop.rect, preset: crop.preset, toLandscape: landscape, imageSize: cropImageSize)
        setCrop(CropRect(rect: rect, preset: crop.preset, isLandscape: landscape))
    }

    /// Turns the photo a quarter clockwise. A crop turns with it, so the same
    /// region stays selected (a fixed ratio flips its orientation).
    func rotatePhoto() {
        var next = look
        next.quarterTurns = FilmLook.normalisedTurns(look.quarterTurns + 1)
        next.crop = look.crop?.turnedClockwise
        applyCrop(next)
    }

    /// Back to the whole, unturned photo (no crop, no turns).
    func resetCrop() {
        guard canResetCrop else { return }
        var next = look
        next.crop = nil
        next.quarterTurns = 0
        applyCrop(next)
    }

    /// Drags the frame by `translation` points while the photo is drawn
    /// `frame` points big. Returns true when it reached a new photo edge.
    @discardableResult
    func moveCrop(from start: CGRect, byPoints translation: CGSize, in frame: CGSize) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let rect = CropGeometry.moved(
            start, by: CGSize(width: translation.width / frame.width, height: translation.height / frame.height)
        )
        return updateCropRect(rect)
    }

    /// Drags `handle` of `start` by `translation` points (see `moveCrop`).
    @discardableResult
    func resizeCrop(_ handle: CropGeometry.Handle, from start: CGRect, byPoints translation: CGSize, in frame: CGSize) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let origin = CropGeometry.position(of: handle, on: start)
        let target = CGPoint(
            x: origin.x + translation.width / frame.width, y: origin.y + translation.height / frame.height
        )
        let rect = CropGeometry.resized(
            start, handle: handle, to: target, imageSize: cropImageSize, ratio: cropRatio(for: cropState)
        )
        return updateCropRect(rect)
    }

    private func updateCropRect(_ rect: CGRect) -> Bool {
        let before = CropGeometry.edgesTouching(cropState.rect)
        var crop = cropState
        crop.x = Double(rect.minX)
        crop.y = Double(rect.minY)
        crop.width = Double(rect.width)
        crop.height = Double(rect.height)
        setCrop(crop)
        return CropGeometry.edgesTouching(rect) > before
    }

    /// Stores `crop`; the whole photo with Original is no crop at all.
    private func setCrop(_ crop: CropRect) {
        var next = look
        next.crop = crop.isFullFrame && crop.preset == .original ? nil : crop
        applyCrop(next)
    }

    /// A crop or turn changes no pixels of the film look, so it never
    /// re-renders while the tool is open (the plain photo is shown).
    private func applyCrop(_ next: FilmLook) {
        guard next != look else { return }
        look = next
        didSaveDownload = false
        if !isCropping { scheduleRender(debounced: false) }
    }

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
    /// The crop and the turns stay: they are geometry, not look (F-122-F).
    func resetToStockDefaults() {
        apply(FilmLook(stock: look.stock, modelVersion: look.modelVersion, crop: look.crop, quarterTurns: look.quarterTurns))
    }

    private func apply(_ next: FilmLook) {
        guard next != look else { return }
        look = next
        // The bar hides Saturation on black and white; don't stay on a hidden tool
        if tool == .saturation && next.rendersInBlackAndWhite { tool = .film }
        didSaveDownload = false
        scheduleRender(debounced: true)
    }

    /// Waits for the newest scheduled render, for callers (and tests) that
    /// need the settled result.
    func renderSettled() async {
        await scheduler.settled()
    }

    /// The look the display render uses: while the Crop tool is open the
    /// whole photo is shown, so the crop waits until the tool is left.
    private var renderLook: FilmLook { isCropping ? look.with(crop: nil) : look }

    private func scheduleRender(debounced: Bool) {
        let look = renderLook
        guard look.altersOutput else {
            scheduler.cancelRender()
            renderedPhoto = photo
            renderedLook = look
            standIn = nil
            isRendering = false
            return
        }
        standIn = geometryStandIn(for: look)
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
                if self.standIn != nil { self.standInSwaps += 1 }
                self.standIn = nil
                self.renderedPhoto = image
                self.renderedLook = look
            case .failed:
                // The previous look stays on screen; the user can edit again
                self.errorState?.raise(.filmLookRenderFailed)
            }
        }
    }

    /// What to show until the render of `look` lands, when its crop or turn
    /// differs from the one on screen; nil when the render on screen already
    /// has that framing (a film edit keeps the old render, as it always did).
    /// The previous render, cropped by the new rect, when it differs from the
    /// new look only by the crop; else the plain photo, turned and cropped.
    private func geometryStandIn(for look: FilmLook) -> UIImage? {
        if let rendered = renderedPhoto, let shown = renderedLook {
            let sameTurns = shown.quarterTurns == look.quarterTurns
            if sameTurns && shown.activeCropRect == look.activeCropRect { return nil }
            if sameTurns && !shown.hasActiveCrop {
                return ImageProcessor.geometryOnly(rendered, look: look.with(quarterTurns: 0))
            }
        }
        // Nothing rendered yet and nothing to frame: the photo itself is shown anyway
        guard renderedPhoto != nil || look.quarterTurns != 0 || look.hasActiveCrop else { return nil }
        return ImageProcessor.geometryOnly(photo, look: look)
    }

    private var seed: UInt64 { StripGenerator.photoLookSeed(for: captureDate) }

    // MARK: Previews (v5.2 M5)

    /// Renders small thumbnails of this photo in every stock and on every
    /// available print, at `size` points × `scale`. Off the main actor,
    /// last request wins, cached per (photo, look without the previewed
    /// stock/print, size) and deterministic (the capture's seed). Results
    /// land in `stockPreviews` and `printPreviews`; a cache hit lands
    /// immediately, and picking a stock re-renders only the prints.
    func requestPreviews(size: CGSize, scale: CGFloat) {
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width >= 1, pixels.height >= 1 else { return }
        previewTask?.cancel()
        previewTask = nil

        // The pickers show the whole photo, so a crop edit is not a new preview
        let look = look.with(crop: nil)
        // Stock previews replace the stock: key on the look without it
        var stockBase = look
        stockBase.stock = .none
        let stockKey = PreviewKey(generation: photoGeneration, look: stockBase, width: Int(pixels.width), height: Int(pixels.height))
        // Print previews replace the print: key on the look without it
        var printBase = look
        printBase.printStock = nil
        let printKey = PreviewKey(generation: photoGeneration, look: printBase, width: Int(pixels.width), height: Int(pixels.height))

        let cachedStocks = stockCache[stockKey]
        let cachedPrints = printCache[printKey]
        if let cachedStocks { stockPreviews = cachedStocks }
        if let cachedPrints { printPreviews = cachedPrints }
        guard cachedStocks == nil || cachedPrints == nil else { return }

        let photo = photo
        let seed = seed
        previewTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .utility) { () -> (stocks: [StripCustomization.FilmStock: UIImage]?, prints: [StripCustomization.PrintStock: UIImage]?)? in
                let source = FilmPreviewThumbnails.source(from: photo, coveringPixelSize: pixels)
                if Task.isCancelled { return nil }
                let stocks = cachedStocks == nil ? FilmPreviewThumbnails.stockPreviews(of: source, look: look, seed: seed) : nil
                if Task.isCancelled { return nil }
                let prints = cachedPrints == nil ? FilmPreviewThumbnails.printPreviews(of: source, look: look, seed: seed) : nil
                return (stocks, prints)
            }.value
            guard let self, !Task.isCancelled, let rendered else { return }
            self.previewRenderCount += 1
            if let stocks = rendered.stocks {
                self.stockCache[stockKey] = stocks
                self.stockPreviews = stocks
            }
            if let prints = rendered.prints {
                self.printCache[printKey] = prints
                self.printPreviews = prints
            }
        }
    }

    /// Waits for the newest `requestPreviews` render, for tests.
    func previewsSettled() async {
        await previewTask?.value
    }

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
    func saveToRoll(context: ModelContext, ending: Outcome = .saved) async -> Bool {
        guard !isSavingToRoll, outcome == nil else { return false }
        isSavingToRoll = true
        defer { isSavingToRoll = false }

        do {
            if let rollPhoto {
                try RollViewModel.update(rollPhoto, look: look, context: context)
            } else {
                let developed = await developedPhoto()
                try RollViewModel.insert(
                    original: developed, look: look, capturedAt: captureDate, context: context, source: newPhotoSource
                )
            }
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
        finish(ending)
        return true
    }

    /// The linked-entry count of the photo being re-edited, read once by
    /// `loadLinkedEntryCount`. nil = not read yet or unreadable.
    private(set) var loadedLinkedEntryCount: Int?

    /// Reads the re-edited photo's linked-entry count (BUG-521-02). Call once
    /// when the editor opens; a fresh capture has nothing to read.
    func loadLinkedEntryCount(context: ModelContext) {
        guard let rollPhoto else { return }
        loadedLinkedEntryCount = RollViewModel.linkedEntryCountIfKnown(for: rollPhoto, in: context)
    }

    /// Continue to diary: a fresh capture, or (BUG-521-02) a re-edit whose
    /// photo has no linked entry yet. An unknown count hides it.
    var canContinueToDiary: Bool {
        guard outcome == nil, !isSavingToRoll else { return false }
        return rollPhoto == nil || loadedLinkedEntryCount == 0
    }

    /// Saves to the Roll exactly like Save to roll (a re-edit updates the
    /// existing photo's look), then exposes `diaryContinuation` and finishes
    /// with `.continuedToDiary`. Returns false (and changes nothing) when not
    /// offered or on failure.
    @discardableResult
    func continueToDiary(context: ModelContext) async -> Bool {
        guard canContinueToDiary else { return false }
        isSavingToRoll = true
        defer { isSavingToRoll = false }

        let developed = await developedPhoto()
        let saved: RollPhoto
        do {
            if let rollPhoto {
                try RollViewModel.update(rollPhoto, look: look, context: context)
                saved = rollPhoto
            } else {
                saved = try RollViewModel.insert(
                    original: developed, look: look, capturedAt: captureDate, context: context, source: newPhotoSource
                )
            }
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
        diaryContinuation = DiaryContinuation(
            rollPhotoID: saved.id, capturedAt: captureDate, photo: developed,
            look: look, displayImage: await promptDisplayImage(of: developed)
        )
        finish(.continuedToDiary)
        return true
    }

    /// The rendered photo the prompt screen starts from. While the Crop tool
    /// is open or a render is pending, the one on screen is not the saved
    /// look (no crop, or the previous one), so it is rendered again.
    private func promptDisplayImage(of developed: UIImage) async -> UIImage? {
        guard isCropping || isRendering, look.altersOutput, let target = displayPixelSize else { return renderedPhoto }
        let look = look
        let seed = seed
        let fresh = await Task.detached(priority: .userInitiated) {
            try? ImageProcessor.renderFullLook(of: developed, look: look, seed: seed, coveringPixelSize: target)
        }.value
        return fresh ?? renderedPhoto
    }

    /// Apply to rest (import only): saves this photo with its look, then ends
    /// with `.appliedToRest` so the batch gives the rest the same look.
    @discardableResult
    func applyToRest(context: ModelContext) async -> Bool {
        guard isImporting, importHasRemaining else { return false }
        return await saveToRoll(context: context, ending: .appliedToRest)
    }

    /// Skip (import only): nothing is saved; the next pick opens.
    func skip() {
        guard isImporting else { return }
        finish(.skipped)
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

    /// Like `linkedEntryCount(in:)` but nil when the count can't be read
    /// (the caller then asks conservatively). 0 for a fresh capture.
    func linkedEntryCountIfKnown(in context: ModelContext) -> Int? {
        guard let rollPhoto else { return 0 }
        return RollViewModel.linkedEntryCountIfKnown(for: rollPhoto, in: context)
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
