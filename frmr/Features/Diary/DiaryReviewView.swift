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

    // v5 F5: the Effects sliders sit behind one row so the photo keeps the room
    @State private var isEffectsExpanded = false

    // Always the dark palette: the screen is a black darkroom around the photo
    private var theme: ThemePalette { ThemePalette.resolve(for: .dark) }

    var body: some View {
        VStack(spacing: Constants.ReviewUI.sectionSpacing) {
            photoArea
            stockRow
            effectsSection
            actionRow
        }
        .padding(.bottom)
        .background(Color.appBlack.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
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
                    DownloadControl(
                        isSaving: review.isSavingDownload,
                        didSave: review.didSaveDownload,
                        isDisabled: review.isDownloadDisabled,
                        identifier: "review.download",
                        savedIdentifier: "review.saved",
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
                        ChoiceChip(
                            label: stock.label,
                            accessibilityLabel: "Film: \(stock.label)",
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

    // v5 F5: Halation, Haze, Light leak, Grain and Vignette as sliders, with
    // Reset to the stock's defaults (OPEN: v5-5). Off has no effects to set.
    @ViewBuilder private var effectsSection: some View {
        if review.stock.hasEffects {
            VStack(spacing: 0) {
                HStack {
                    Button(action: toggleEffects) {
                        HStack(spacing: Constants.ReviewUI.stockChipSpacing) {
                            Text("Effects")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: isEffectsExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.appCream)
                        .frame(minHeight: Constants.ReviewUI.stockChipHeight)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isEffectsExpanded ? "Hides the effect sliders" : "Shows the effect sliders")
                    .accessibilityIdentifier("review.effects")
                    Spacer()
                    if isEffectsExpanded {
                        Button("Reset", action: review.resetToStockDefaults)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appCream)
                            .disabled(review.look.isStockDefault)
                            .accessibilityHint("Restores this film's own effect strengths")
                            .accessibilityIdentifier("review.effects.reset")
                    }
                }
                if isEffectsExpanded {
                    ScrollView {
                        EffectSliders(
                            strength: { review.look.strengths[$0] },
                            setStrength: { review.setStrength($0, for: $1) },
                            identifierPrefix: "review.slider",
                            textColor: Color.appCream,
                            tint: theme.primary
                        )
                    }
                    .frame(maxHeight: Constants.ReviewUI.effectsMaxHeight)
                }
            }
            .padding(.horizontal)
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

    private func toggleEffects() {
        withAnimation(.easeInOut(duration: Constants.ReviewUI.feedbackAnimationDuration)) {
            isEffectsExpanded.toggle()
        }
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
