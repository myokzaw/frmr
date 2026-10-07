import SwiftData
import SwiftUI

// Shown after a diary capture: photo on top, prompt, text entry, save.
// The photo comes from the camera view model so the processed RAW can
// replace the JPEG preview while the user is already writing.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ErrorState.self) private var errorState

    let camera: CameraViewModel
    @State private var viewModel = DiaryViewModel()

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                CapturedPhotoHeader(image: camera.pendingDiaryImage)
                    .frame(height: geometry.size.height * Constants.EditorUI.photoHeightFraction)
                    .clipped()
                editorForm
            }
        }
        .background(theme.background)
        .appErrorAlert(errorState)
        .task {
            viewModel.errorState = errorState
            viewModel.prepareNewEntry()
        }
    }

    private var editorForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.EditorUI.buttonPadding) {
                PromptCard(prompt: viewModel.prompt, textColor: theme.text)

                TextEditor(text: Bindable(viewModel).responseText.projectedValue)
                    .font(.system(size: Constants.EditorUI.entryFontSize, design: .serif))
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Constants.EditorUI.entryMinHeight)
                    .padding(Constants.EditorUI.buttonPadding / 2)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: Constants.EditorUI.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.EditorUI.cardCornerRadius)
                            .strokeBorder(theme.cardBorder)
                    )

                CharacterCountIndicator(
                    text: viewModel.characterCountText,
                    isVisible: viewModel.isCharacterCountVisible
                )

                Button(action: saveEntry) {
                    Text("Save entry")
                        .font(.system(size: Constants.EditorUI.entryFontSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(Constants.EditorUI.buttonPadding)
                        .background(theme.primary, in: RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius))
                }

                HStack(spacing: Constants.EditorUI.linkSpacing) {
                    Button("Retake", action: retake)
                    // OPEN: Skip confirmation dialog TBD (project.md §13 #3) — none for now
                    Button("Skip", action: skipText)
                }
                .font(.system(size: Constants.EditorUI.linkFontSize, weight: .medium))
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private func saveEntry() {
        if viewModel.saveEntry(image: camera.pendingDiaryImage, includeText: true, context: modelContext) {
            camera.discardPendingDiaryImage()
        }
    }

    // "Skip" keeps the photo but saves the entry without text (project.md §3)
    private func skipText() {
        if viewModel.saveEntry(image: camera.pendingDiaryImage, includeText: false, context: modelContext) {
            camera.discardPendingDiaryImage()
        }
    }

    private func retake() {
        camera.discardPendingDiaryImage()
    }
}

private struct CapturedPhotoHeader: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.appBlack
        }
    }
}
