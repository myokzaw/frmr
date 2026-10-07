import Observation
import PhotosUI
import SwiftUI

@Observable
final class PhotoboothViewModel {
    var errorState: ErrorState?

    private(set) var shots: [UIImage] = []
    var pickerItems: [PhotosPickerItem] = []
    var isStripPresented = false

    var slotCount: Int { Constants.entriesPerStrip }
    var isFull: Bool { shots.count >= slotCount }
    var canGenerate: Bool { !shots.isEmpty }
    var hasShots: Bool { !shots.isEmpty }
    var remainingSlots: Int { slotCount - shots.count }

    var capturedCountText: String {
        "live viewfinder — \(shots.count) of \(slotCount) captured"
    }

    // Photobooth shots carry no captions and no diary entries
    var stripItems: [StripItem] {
        shots.map { StripItem(image: $0, caption: "", entryID: nil) }
    }

    func image(at index: Int) -> UIImage? {
        index < shots.count ? shots[index] : nil
    }

    // OPEN: auto-advance vs deliberate tap per slot TBD (project.md §13 #2) —
    // auto-advance default: each capture fills the next empty slot
    func add(_ image: UIImage) {
        guard !isFull else { return }
        shots.append(image)
    }

    func removeLastShot() {
        guard !shots.isEmpty else { return }
        shots.removeLast()
    }

    func clear() {
        shots = []
    }

    // Gallery photos are used as-is, not re-processed (open decision #6 default)
    func loadPickerSelection() async {
        defer { pickerItems = [] }
        for item in pickerItems {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorState?.raise(.captureFailed(reason: "A selected photo couldn't be read."))
                    continue
                }
                add(image)
            } catch {
                errorState?.raise(.captureFailed(reason: "A selected photo couldn't be loaded."))
            }
        }
    }
}
