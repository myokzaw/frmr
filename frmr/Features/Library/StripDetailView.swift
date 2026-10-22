import SwiftUI

// Full-screen view of a saved strip, presented from the Library's Strips tab
// (v5.1 F10): the strip as the hero, a glass top bar with close and save
// icons, the date in the bar.
struct StripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ErrorState.self) private var errorState

    let image: UIImage?
    let dateText: String
    let onSaveToCameraRoll: () -> Void

    var body: some View {
        detailContent
            .appErrorAlert(errorState)
    }

    private var detailContent: some View {
        ZStack {
            Color.appBlack
                .ignoresSafeArea()

            StripImage(image: image)
                .padding(.horizontal, Constants.DetailUI.photoInset)
                .padding(.top, Constants.DetailUI.stripInset)
                .padding(.bottom, Constants.DetailUI.photoInset)

            VStack {
                DetailTopBar(title: dateText, onClose: { dismiss() }) {
                    GlassIconButton(
                        systemImage: "square.and.arrow.down",
                        label: "Save to camera roll",
                        identifier: "detail.save",
                        isEnabled: image != nil,
                        action: onSaveToCameraRoll
                    )
                }
                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StripImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Constants.LibraryUI.stripCornerRadius))
                .shadow(
                    color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                    radius: Constants.StripUI.previewShadowRadius / 2
                )
                .accessibilityLabel("Film strip")
        } else {
            Text("This strip file is missing.")
                .font(.callout)
                .foregroundStyle(.white.opacity(Constants.DetailUI.promptOpacity))
        }
    }
}

#Preview {
    StripDetailView(image: nil, dateText: "Today", onSaveToCameraRoll: {})
        .environment(ErrorState())
}
