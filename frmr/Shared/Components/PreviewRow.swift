import SwiftUI

/// A horizontal row of this photo in each choice (stocks or prints). The
/// selected one wears an amber ring; while a thumbnail renders a spinner
/// stands in. Inset by content margins, so the first and last never clip.
struct PreviewRow<Choice: Hashable>: View {
    let choices: [Choice]
    let selected: Choice?
    let image: (Choice) -> UIImage?
    let code: (Choice) -> String
    let label: (Choice) -> String
    let identifier: (Choice) -> String
    let ringColor: Color
    let textColor: Color
    let onSelect: (Choice) -> Void

    private typealias UI = Constants.PhotoEditUI

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: UI.previewSpacing) {
                    ForEach(choices, id: \.self) { choice in
                        PreviewThumb(
                            image: image(choice),
                            code: code(choice),
                            isSelected: choice == selected,
                            ringColor: ringColor,
                            textColor: textColor,
                            action: { onSelect(choice) }
                        )
                        .id(choice)
                        .accessibilityLabel(label(choice))
                        .accessibilityIdentifier(identifier(choice))
                    }
                }
            }
            .contentMargins(.horizontal, UI.horizontalPadding, for: .scrollContent)
            .onAppear {
                if let selected { proxy.scrollTo(selected, anchor: .center) }
            }
        }
    }
}

struct PreviewThumb: View {
    let image: UIImage?
    let code: String
    let isSelected: Bool
    let ringColor: Color
    let textColor: Color
    let action: () -> Void

    private typealias UI = Constants.PhotoEditUI
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: UI.previewLabelSpacing) {
                Color.white.opacity(Constants.CameraUI.chipInactiveOpacity)
                    .frame(width: UI.previewWidth, height: UI.previewHeight)
                    .overlay { PreviewImage(image: image) }
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(isSelected ? ringColor : .clear, lineWidth: UI.previewRingWidth)
                    }
                Text(code)
                    .frmrCodeStyle()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? ringColor : textColor)
                    .frame(width: UI.previewWidth + UI.previewSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PreviewImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ProgressView()
                .tint(.white)
        }
    }
}
