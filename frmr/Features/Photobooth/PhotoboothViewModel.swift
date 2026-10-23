import Observation
import PhotosUI
import SwiftUI

// One photobooth frame (v4 F11): the original photo plus the stock it was
// taken on. The look is applied only when the strip renders.
struct PhotoboothShot {
    let image: UIImage
    let filmStock: StripCustomization.FilmStock
    /// A Roll photo's full look (stock, print, B&W, strengths), v5-8; nil for
    /// camera and gallery shots, which carry only their stock.
    let look: FilmLook?

    init(image: UIImage, filmStock: StripCustomization.FilmStock, look: FilmLook? = nil) {
        self.image = image
        self.filmStock = look?.stock ?? filmStock
        self.look = look
    }
}

@Observable
final class PhotoboothViewModel {
    var errorState: ErrorState?

    private(set) var shots: [PhotoboothShot] = []
    var pickerItems: [PhotosPickerItem] = []
    var isStripPresented = false

    var slotCount: Int { Constants.entriesPerStrip }
    var isFull: Bool { shots.count >= slotCount }
    var canGenerate: Bool { !shots.isEmpty }
    var hasShots: Bool { !shots.isEmpty }
    var remainingSlots: Int { slotCount - shots.count }

    /// "1 of 4": shots taken so far out of the strip's slots.
    /// "2/4": the strip's fill, for the mini-strip badge.
    var stripProgressBadge: String { "\(shots.count)/\(slotCount)" }
    var stripProgressText: String { "\(shots.count) of \(slotCount)" }

    var capturedCountText: String {
        "live viewfinder — \(shots.count) of \(slotCount) captured"
    }

    // Photobooth shots carry no captions and no diary entries
    var stripItems: [StripItem] {
        shots.map { StripItem(image: $0.image, caption: "", entryID: nil, filmStock: $0.filmStock, look: $0.look) }
    }

    /// The slot's original photo, without its stock's look.
    func image(at index: Int) -> UIImage? {
        index < shots.count ? shots[index].image : nil
    }

    func shot(at index: Int) -> PhotoboothShot? {
        index < shots.count ? shots[index] : nil
    }

    // OPEN: auto-advance vs deliberate tap per slot TBD (project.md §13 #2) —
    // auto-advance default: each capture fills the next empty slot.
    // `filmStock` is the camera's stock at capture; the default keeps the
    // pre-F9 camera call site compiling until it passes one.
    func add(_ image: UIImage, filmStock: StripCustomization.FilmStock = .none) {
        add(PhotoboothShot(image: image, filmStock: filmStock))
    }

    /// A camera capture, already carrying the camera's stock (v4 F9).
    func add(_ shot: PhotoboothShot) {
        guard !isFull else { return }
        shots.append(shot)
    }

    /// A Roll photo joins a slot linked (v5-8): its original image plus its
    /// current full look, rendered at Generate time exactly like
    /// `RollViewModel.stripItems(from:)`. Does nothing when the strip is full
    /// or the file can't be read.
    func add(rollPhoto: RollPhoto) {
        guard !isFull, let image = RollViewModel.loadPhoto(for: rollPhoto) else { return }
        add(PhotoboothShot(image: image, filmStock: rollPhoto.look.stock, look: rollPhoto.look))
    }

    func removeLastShot() {
        guard !shots.isEmpty else { return }
        shots.removeLast()
    }

    func clear() {
        shots = []
    }

    // Gallery photos are used as-is, not re-processed (open decision #6 default).
    // OPEN: v4-12 — a gallery pick takes the camera's current stock at pick
    // time. The camera persists every change, so the stored value is the
    // live one; the default reads it, which keeps the existing call site
    // correct without access to the CameraViewModel.
    func loadPickerSelection(
        filmStock: StripCustomization.FilmStock = Constants.Camera.galleryPicksUseCameraStock
            ? CameraViewModel.storedFilmStock(in: .standard) : .none
    ) async {
        defer { pickerItems = [] }
        for item in pickerItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorState?.raise(.captureFailed(reason: "A selected photo couldn't be read."))
                    continue
                }
                add(image, filmStock: filmStock)
            } catch {
                errorState?.raise(.captureFailed(reason: "A selected photo couldn't be loaded."))
            }
        }
    }
}
