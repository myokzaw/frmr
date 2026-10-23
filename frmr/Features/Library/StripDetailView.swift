import SwiftUI

// Full-screen view of a saved strip, presented from the Library's Strips tab
// (v5.1 F10, v5.2 §5.7): the strip as the hero on the darkroom, Close on
// glass at the top left and [Share, Download] at the top right. The date is
// printed on the strip itself, so the bar carries no title.
struct StripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState

    let image: UIImage?
    let dateText: String
    let onSaveToCameraRoll: () -> Void

    private var theme: ThemePalette { ThemePalette.resolve(for: .dark, surface: .darkroom, contrast: contrast) }

    var body: some View {
        StripImage(image: image, dateText: dateText, mutedColor: theme.textMuted)
            .padding(.horizontal, Constants.DesignUI.Space.xxl)
            .padding(.vertical, Constants.DesignUI.Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                DetailTopBar(onClose: { dismiss() }) {
                    if let image {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Film strip", image: Image(uiImage: image))) {
                            GlassIconGlyph(systemImage: "square.and.arrow.up", rotates: false)
                        }
                        .accessibilityLabel("Share")
                        .accessibilityIdentifier("detail.share")
                    }
                    GlassIconButton(
                        systemImage: "arrow.down.to.line",
                        label: "Download",
                        identifier: "detail.save",
                        isEnabled: image != nil,
                        rotates: false,
                        action: onSaveToCameraRoll
                    )
                    .accessibilityHint("Saves the strip to your photo library")
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .frmrDarkroomStatusBar()
            .appErrorAlert(errorState)
    }
}

private struct StripImage: View {
    let image: UIImage?
    let dateText: String
    let mutedColor: Color

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
                .shadow(
                    color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                    radius: Constants.StripUI.previewShadowRadius / 2
                )
                .accessibilityLabel("Film strip from \(dateText)")
        } else {
            Text("This strip file is missing.")
                .font(.frmrMeta)
                .foregroundStyle(mutedColor)
        }
    }
}

#Preview {
    StripDetailView(image: nil, dateText: "Today", onSaveToCameraRoll: {})
        .environment(ErrorState())
}
