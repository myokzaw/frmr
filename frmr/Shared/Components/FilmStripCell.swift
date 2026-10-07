import SwiftUI

// One on-screen cell of a film strip preview: square photo with its caption
// below. Rendering for export uses StripGenerator, not this view.
struct FilmStripCell: View {
    let image: UIImage?
    let caption: String

    var body: some View {
        VStack(spacing: Constants.Strip.captionSpacing) {
            PhotoSlot(image: image)
            Text(caption)
                .font(.system(size: Constants.Strip.captionFontSize, design: .serif))
                .italic()
                .foregroundStyle(Color.appBlack)
                .lineLimit(Constants.Strip.captionMaxLines)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PhotoSlot: View {
    let image: UIImage?

    var body: some View {
        Color.appBlack.opacity(Constants.Strip.emptySlotAlpha)
            .aspectRatio(Constants.Strip.cellAspectRatio, contentMode: .fit)
            .overlay(SlotImage(image: image))
            .clipped()
    }
}

private struct SlotImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }
}

#Preview {
    FilmStripCell(image: nil, caption: "a quiet morning")
        .frame(width: 150)
        .padding()
}
