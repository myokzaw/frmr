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
    var selectedForeground: Color = .white
    // Dark pages (the editor) use the defaults; the strip screen follows the
    // light or dark theme
    var idleForeground: Color = .white
    var idleBackground: Color = .white.opacity(Constants.CameraUI.chipInactiveOpacity)
    let action: () -> Void

    private var background: Color {
        isSelected ? selectedColor : idleBackground
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.frmrLabel.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? selectedForeground : idleForeground)
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
        if isVisible {
            ProgressView()
                .tint(.white)
                .padding(Constants.ReviewUI.savedVerticalPadding)
                .frmrGlass(in: Circle())
                .accessibilityLabel("Rendering")
        }
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
            // Inserted, not faded: iOS 26 glass ignores opacity inside a container
            if didSave {
                SavedBadge(identifier: savedIdentifier)
                    .transition(.opacity)
            }
            Button(action: action) {
                ZStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: symbolName)
                            .font(.system(size: Constants.ScrubberUI.glassButtonIconSize, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: Constants.ReviewUI.downloadButtonSize, height: Constants.ReviewUI.downloadButtonSize)
                .frmrGlass(in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled && !isSaving ? Constants.CameraUI.disabledControlOpacity : 1)
            .accessibilityLabel("Download photo")
            .accessibilityValue(didSave ? "Saved" : "")
            .accessibilityHint("Saves this photo with its film look to your photo library")
            .accessibilityIdentifier(identifier)
        }
        .frmrAnimation(.snap, value: didSave)
    }
}

private struct SavedBadge: View {
    let identifier: String

    var body: some View {
        Text("Saved")
            .font(.frmrMeta.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Constants.ReviewUI.savedHorizontalPadding)
            .padding(.vertical, Constants.ReviewUI.savedVerticalPadding)
            .frmrGlassCapsule()
            .accessibilityIdentifier(identifier)
    }
}
