import SwiftUI

// v5 F6: a Roll photo shown through its own current look, rendered for the
// size this view is drawn at (same pattern as EntryLookImage). A cached
// render shows on the first frame; otherwise the placeholder stays until the
// render lands, so the plain original never flashes before the look. The
// task re-runs when the look or the size changes, so a re-edit shows at once.
struct RollLookImage<Missing: View>: View {
    @Environment(\.displayScale) private var displayScale

    let photo: RollPhoto
    let contentMode: ContentMode
    @ViewBuilder let missing: () -> Missing

    @State private var loaded: LoadedRollLook?

    var body: some View {
        GeometryReader { geometry in
            // Color.clear keeps a real view under the task while nothing
            // is shown yet; a bare empty branch would never start it
            ZStack {
                Color.clear
                content(for: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: RollLookKey(photoID: photo.id, look: photo.look, size: geometry.size)) {
                // The first layout pass can report zero; wait for a real size
                guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                let image = await RollViewModel.displayImage(for: photo, size: geometry.size, scale: displayScale)
                loaded = LoadedRollLook(image: image)
            }
        }
    }

    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        if let image = RollViewModel.cachedDisplayImage(for: photo, size: size, scale: displayScale) ?? loaded?.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if loaded != nil {
            missing()
        }
    }
}

// Distinguishes "not rendered yet" (nil) from "the file is missing"
// (a LoadedRollLook holding nil)
private struct LoadedRollLook {
    let image: UIImage?
}

private struct RollLookKey: Hashable {
    let photoID: UUID
    let look: FilmLook
    let width: CGFloat
    let height: CGFloat

    init(photoID: UUID, look: FilmLook, size: CGSize) {
        self.photoID = photoID
        self.look = look
        self.width = size.width
        self.height = size.height
    }
}
