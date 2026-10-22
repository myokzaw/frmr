import SwiftData
import SwiftUI

// The prompt screen (v5.1 F4/F10), shown after "Continue to diary": the
// edited photo full bleed under rounded corners, a typewriter prompt, a
// quiet writing card, Save entry (primary) and Skip (secondary). The photo
// is already in the Roll; the entry links to it, so nothing is copied here.
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
                CapturedPhotoHeader(image: camera.pendingDiaryDisplayImage)
                    .frame(height: geometry.size.height * Constants.EditorUI.photoHeightFraction)
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: Constants.EditorUI.headerCornerRadius,
                        bottomTrailingRadius: Constants.EditorUI.headerCornerRadius
                    ))
                    .ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)
                editorForm
            }
        }
        .background(theme.background.ignoresSafeArea())
        .appErrorAlert(errorState)
        .task {
            viewModel.errorState = errorState
            viewModel.prepareNewEntry()
        }
    }

    private var editorForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.EditorUI.formSpacing) {
                PromptCard(prompt: viewModel.prompt, textColor: theme.text)

                TextEditor(text: Bindable(viewModel).responseText.projectedValue)
                    .font(.system(size: Constants.EditorUI.entryFontSize, design: .serif))
                    .foregroundStyle(theme.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: Constants.EditorUI.entryMinHeight)
                    .padding(Constants.EditorUI.buttonPadding / 2)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: Constants.EditorUI.cardCornerRadius))
                    .accessibilityLabel("Your reflection")
                    .accessibilityIdentifier("entry.text")

                CharacterCountIndicator(
                    text: viewModel.characterCountText,
                    isVisible: viewModel.isCharacterCountVisible,
                    color: theme.muted
                )

                Button(action: saveEntry) {
                    Text("Save entry")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appBlack)
                        .frame(maxWidth: .infinity, minHeight: Constants.EditorUI.primaryButtonHeight)
                        .background(Color.appAmber, in: RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("entry.save")

                // OPEN: Skip confirmation dialog TBD (project.md §13 #3) — none for now
                Button(action: skipText) {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, minHeight: Constants.EditorUI.skipButtonHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Keeps the photo and saves the entry without text")
                .accessibilityIdentifier("entry.skip")
            }
            .padding()
        }
    }

    private func saveEntry() {
        save(includeText: true)
    }

    // "Skip" keeps the photo but saves the entry without text (project.md §3)
    private func skipText() {
        save(includeText: false)
    }

    private func save(includeText: Bool) {
        if viewModel.saveEntry(
            image: camera.pendingDiaryImage,
            filmStock: camera.pendingDiaryStock,
            look: camera.pendingDiaryLook,
            capturedAt: camera.pendingDiaryCaptureDate,
            rollPhotoID: camera.pendingDiaryRollPhotoID,
            includeText: includeText,
            context: modelContext
        ) {
            camera.endDiaryPrompt()
        }
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
