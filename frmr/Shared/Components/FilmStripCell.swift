import SwiftUI

// One on-screen cell of a film strip preview: a 4:5 portrait frame with
// soft corners and a one-line caption band below (v4 F15 booth layout). Rendering for export uses StripGenerator, not this view.
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
                .lineLimit(Constants.Strip.boothCaptionLines)
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
            .clipShape(RoundedRectangle(cornerRadius: Constants.Strip.frameCornerRadius))
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
