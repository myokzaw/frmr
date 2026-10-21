import SwiftUI

// v4 F11: a diary entry's photo shown through its own stock, rendered for
// the size this view is drawn at. A cached render shows on the first frame;
// otherwise the placeholder stays until the render lands, so the plain
// original never flashes before the look.
struct EntryLookImage<Missing: View>: View {
    @Environment(\.displayScale) private var displayScale

    let entry: DiaryEntry
    let contentMode: ContentMode
    @ViewBuilder let missing: () -> Missing

    @State private var loaded: LoadedLook?

    var body: some View {
        GeometryReader { geometry in
            // Color.clear keeps a real view under the task while nothing
            // is shown yet; a bare empty branch would never start it
            ZStack {
                Color.clear
                content(for: geometry.size)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
                .task(id: LookKey(entryID: entry.id, stock: entry.filmStock, size: geometry.size)) {
                    // The first layout pass can report zero; wait for a real size
                    guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                    let image = await DiaryViewModel.displayImage(for: entry, size: geometry.size, scale: displayScale)
                    loaded = LoadedLook(image: image)
                }
        }
    }

    @ViewBuilder
    private func content(for size: CGSize) -> some View {
        if let image = loaded?.image ?? DiaryViewModel.cachedDisplayImage(for: entry, size: size, scale: displayScale) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if loaded != nil {
            missing()
        }
    }
}

// Distinguishes "not rendered yet" (nil) from "the file is missing"
// (a LoadedLook holding nil)
private struct LoadedLook {
    let image: UIImage?
}

private struct LookKey: Hashable {
    let entryID: UUID
    let stock: StripCustomization.FilmStock
    let width: CGFloat
    let height: CGFloat

    init(entryID: UUID, stock: StripCustomization.FilmStock, size: CGSize) {
        self.entryID = entryID
        self.stock = stock
        self.width = size.width
        self.height = size.height
    }
}
