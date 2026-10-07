import SwiftUI

// Full-screen view of a saved strip, presented from the Library's Strips tab.
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
        ZStack(alignment: .topLeading) {
            Color.appBlack
                .ignoresSafeArea()

            VStack(spacing: Constants.EditorUI.buttonPadding) {
                StripImage(image: image)
                Text(dateText)
                    .font(.system(size: Constants.LibraryUI.sectionFontSize, design: .monospaced))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(Color.appTealLight)
                SaveToCameraRollButton(isEnabled: image != nil, action: onSaveToCameraRoll)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            CloseCircleButton(action: { dismiss() })
                .padding()
        }
    }
}

private struct SaveToCameraRollButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Save to camera roll", systemImage: "square.and.arrow.down")
                .font(.system(size: Constants.StripUI.actionFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Constants.EditorUI.buttonPadding)
                .padding(.vertical, Constants.CameraUI.generateButtonVerticalPadding)
                .background(Color.appTeal, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Constants.CameraUI.disabledControlOpacity)
    }
}

private struct StripImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .shadow(
                    color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                    radius: Constants.StripUI.previewShadowRadius / 2
                )
        } else {
            Text("This strip file is missing.")
                .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
                .italic()
                .foregroundStyle(Color.appCream.opacity(Constants.CameraUI.captionOpacity))
        }
    }
}

#Preview {
    StripDetailView(image: nil, dateText: "Today", onSaveToCameraRoll: {})
        .environment(ErrorState())
}
