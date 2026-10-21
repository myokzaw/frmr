import SwiftUI

// v4 F10 review step between the shutter and the prompt screen: the photo in
// its stock, a stock row to change it, OK (bottom left) and Retake (bottom
// right). v4 F13 adds Download at the top right of the photo. Every decision
// lives in DiaryReviewViewModel / CameraViewModel; this view only reports
// its photo size and forwards taps.
struct DiaryReviewView: View {
    @Environment(ErrorState.self) private var errorState
    @Environment(\.displayScale) private var displayScale

    let review: DiaryReviewViewModel
    let onConfirm: () -> Void
    let onRetake: () -> Void

    // Always the dark palette: the screen is a black darkroom around the photo
    private var theme: ThemePalette { ThemePalette.resolve(for: .dark) }

    var body: some View {
        VStack(spacing: Constants.ReviewUI.sectionSpacing) {
            photoArea
            stockRow
            actionRow
        }
        .padding(.bottom)
        .background(Color.appBlack.ignoresSafeArea())
        .appErrorAlert(errorState)
        .task { review.errorState = errorState }
    }

    // The renderer must know the drawn size before its first render
    private var photoArea: some View {
        GeometryReader { geometry in
            // Overlays go on the fitted photo, not the whole area, so
            // Download sits on the photo's own top-right corner
            ReviewPhoto(image: review.renderedPhoto ?? review.photo)
                .overlay(alignment: .bottomLeading) {
                    RenderingIndicator(isVisible: review.isRendering || review.isDevelopingPhoto)
                        .padding()
                }
                .overlay(alignment: .topTrailing) {
                    DownloadButton(
                        isSaving: review.isSavingDownload,
                        didSave: review.didSaveDownload,
                        isDisabled: review.isDownloadDisabled,
                        action: download
                    )
                    .padding()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear { review.setDisplaySize(geometry.size, scale: displayScale) }
                .onChange(of: geometry.size) { _, size in
                    review.setDisplaySize(size, scale: displayScale)
                }
        }
    }

    // Seven full names don't fit across a phone, so the row scrolls; it
    // opens centred on the capture's stock so the selection is visible
    private var stockRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Constants.ReviewUI.stockChipSpacing) {
                    ForEach(review.stockChoices) { stock in
                        ReviewStockChip(
                            label: stock.label,
                            identifier: "review.stock.\(stock.rawValue)",
                            isSelected: stock == review.stock,
                            selectedColor: theme.primary,
                            action: { review.selectStock(stock) }
                        )
                        .id(stock)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { proxy.scrollTo(review.stock, anchor: .center) }
        }
    }

    // OK bottom left (primary), Retake bottom right (secondary): user decision
    private var actionRow: some View {
        HStack(spacing: Constants.ReviewUI.sectionSpacing) {
            Button(action: onConfirm) {
                Text("OK")
                    .font(.system(size: Constants.EditorUI.entryFontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Constants.ReviewUI.actionButtonHeight)
                    .background(theme.primary, in: RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Keeps this photo and film and opens the prompt")
            .accessibilityIdentifier("review.ok")

            Button(action: onRetake) {
                Text("Retake")
                    .font(.system(size: Constants.EditorUI.entryFontSize, weight: .semibold))
                    .foregroundStyle(Color.appCream)
                    .frame(maxWidth: .infinity, minHeight: Constants.ReviewUI.actionButtonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius)
                            .strokeBorder(theme.cardBorder)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Discards this photo and returns to the camera")
            .accessibilityIdentifier("review.retake")
        }
        .padding(.horizontal)
    }

    private func download() {
        Task { await review.downloadReview() }
    }
}

private struct ReviewPhoto: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Captured photo")
    }
}

// Small and quiet: the previous look stays on screen while the next renders
private struct RenderingIndicator: View {
    let isVisible: Bool

    var body: some View {
        ProgressView()
            .tint(.white)
            .padding(Constants.ReviewUI.savedVerticalPadding)
            .background(.black.opacity(Constants.ReviewUI.overlayOpacity), in: Circle())
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: Constants.ReviewUI.feedbackAnimationDuration), value: isVisible)
            .accessibilityLabel("Rendering")
            .accessibilityHidden(!isVisible)
    }
}

private struct DownloadButton: View {
    let isSaving: Bool
    let didSave: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var symbolName: String { didSave ? "checkmark" : "arrow.down.to.line" }

    var body: some View {
        HStack(spacing: Constants.ReviewUI.stockChipSpacing) {
            SavedBadge(isVisible: didSave)
            Button(action: action) {
                ZStack {
                    Image(systemName: symbolName)
                        .font(.system(size: Constants.ReviewUI.downloadIconSize, weight: .semibold))
                        .opacity(isSaving ? 0 : 1)
                    ProgressView()
                        .tint(.white)
                        .opacity(isSaving ? 1 : 0)
                }
                .foregroundStyle(.white)
                .frame(width: Constants.ReviewUI.downloadButtonSize, height: Constants.ReviewUI.downloadButtonSize)
                .background(.black.opacity(Constants.ReviewUI.overlayOpacity), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled && !isSaving ? Constants.CameraUI.disabledControlOpacity : 1)
            .accessibilityLabel("Download photo")
            .accessibilityValue(didSave ? "Saved" : "")
            .accessibilityHint("Saves this photo with its film look to your photo library")
            .accessibilityIdentifier("review.download")
        }
        .animation(.easeInOut(duration: Constants.ReviewUI.feedbackAnimationDuration), value: didSave)
    }
}

private struct SavedBadge: View {
    let isVisible: Bool

    var body: some View {
        Text("Saved")
            .font(.system(size: Constants.ReviewUI.savedFontSize, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Constants.ReviewUI.savedHorizontalPadding)
            .padding(.vertical, Constants.ReviewUI.savedVerticalPadding)
            .background(.black.opacity(Constants.ReviewUI.overlayOpacity), in: Capsule())
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(!isVisible)
            .accessibilityIdentifier("review.saved")
    }
}

private struct ReviewStockChip: View {
    let label: String
    let identifier: String
    let isSelected: Bool
    let selectedColor: Color
    let action: () -> Void

    private var background: Color {
        isSelected ? selectedColor : .white.opacity(Constants.CameraUI.chipInactiveOpacity)
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Constants.ReviewUI.stockChipFontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, Constants.ReviewUI.stockChipHorizontalPadding)
                .frame(minHeight: Constants.ReviewUI.stockChipHeight)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Film: \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
