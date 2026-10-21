import SwiftUI

// Small controls shared by the diary review (v4 F10/F13) and the Photo
// editor (v5 F4): a selectable chip, the quiet "rendering" spinner and the
// Download button with its Saved confirmation. Pure presentation: every
// state arrives as a parameter.

struct ChoiceChip: View {
    let label: String
    let accessibilityLabel: String
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// Small and quiet: the previous look stays on screen while the next renders
struct RenderingIndicator: View {
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

struct DownloadControl: View {
    let isSaving: Bool
    let didSave: Bool
    let isDisabled: Bool
    let identifier: String
    let savedIdentifier: String
    let action: () -> Void

    private var symbolName: String { didSave ? "checkmark" : "arrow.down.to.line" }

    var body: some View {
        HStack(spacing: Constants.ReviewUI.stockChipSpacing) {
            SavedBadge(isVisible: didSave, identifier: savedIdentifier)
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
            .accessibilityIdentifier(identifier)
        }
        .animation(.easeInOut(duration: Constants.ReviewUI.feedbackAnimationDuration), value: didSave)
    }
}

private struct SavedBadge: View {
    let isVisible: Bool
    let identifier: String

    var body: some View {
        Text("Saved")
            .font(.system(size: Constants.ReviewUI.savedFontSize, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Constants.ReviewUI.savedHorizontalPadding)
            .padding(.vertical, Constants.ReviewUI.savedVerticalPadding)
            .background(.black.opacity(Constants.ReviewUI.overlayOpacity), in: Capsule())
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(!isVisible)
            .accessibilityIdentifier(identifier)
    }
}
