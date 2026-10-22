import SwiftData
import SwiftUI

// The prompt screen (v5.1 F4, v5.2 S4), shown after "Continue to diary" in
// the editor's cover: the edited photo as a 4:5 header on paper, the
// typewriter prompt (never truncated: its full height is reserved), a quiet
// writing surface under a hairline rule, and Save entry riding the
// keyboard. Skip sits top right. While typing, the photo shrinks to a
// thumbnail beside the prompt. The photo is already in the Roll; the entry
// links to it, so nothing is copied here.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState

    let camera: CameraViewModel
    @State private var viewModel = DiaryViewModel()
    @FocusState private var isWriting: Bool

    private typealias UI = Constants.EditorUI
    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UI.formSpacing) {
                header
                Divider()
                    .overlay(theme.cardBorder)
                writingSurface
                CharacterCountIndicator(
                    text: viewModel.characterCountText,
                    isVisible: viewModel.isCharacterCountVisible,
                    isWarning: CharacterCountIndicator.isWarning(count: viewModel.responseText.count),
                    color: theme.textMuted,
                    warningColor: theme.destructive
                )
            }
            .padding(.horizontal, Constants.DesignUI.gutter)
            .frmrAnimation(.panel, value: isWriting)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .background(theme.bg.ignoresSafeArea())
        .foregroundStyle(theme.text)
        .tint(theme.tint)
        .appErrorAlert(errorState)
        .task {
            viewModel.errorState = errorState
            viewModel.prepareNewEntry()
        }
    }

    // Skip keeps the photo and saves the entry without text (project.md §3)
    // OPEN: Skip confirmation dialog TBD (project.md §13 #3) — none for now
    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: skipText) {
                Text("Skip")
                    .font(.frmrLabel)
                    .foregroundStyle(theme.tint)
                    .frame(minWidth: Constants.DesignUI.targetMin, minHeight: Constants.DesignUI.targetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Keeps the photo and saves the entry without text")
                .accessibilityIdentifier("entry.skip")
        }
        .padding(.horizontal, Constants.DesignUI.gutter)
        .background(theme.bg)
    }

    // The photo above the prompt; a thumbnail beside it while typing
    @ViewBuilder private var header: some View {
        if isWriting {
            HStack(alignment: .top, spacing: Constants.DesignUI.Space.m) {
                EntryHeaderPhoto(image: camera.pendingDiaryDisplayImage)
                    .frame(width: UI.thumbnailSize, height: UI.thumbnailSize / Constants.CameraUI.stripFrameAspect)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
                PromptCard(prompt: viewModel.prompt, textColor: theme.text)
            }
        } else {
            EntryHeaderPhoto(image: camera.pendingDiaryDisplayImage)
                .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: UI.photoMaxHeight)
                .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.media))
                .frame(maxWidth: .infinity)
            PromptCard(prompt: viewModel.prompt, textColor: theme.text)
        }
    }

    private var writingSurface: some View {
        TextEditor(text: Bindable(viewModel).responseText.projectedValue)
            .font(.frmrReading)
            .foregroundStyle(theme.text)
            .scrollContentBackground(.hidden)
            .focused($isWriting)
            .frame(minHeight: UI.entryMinHeight)
            .overlay(alignment: .topLeading) {
                Text("A line or two is enough.")
                    .font(.frmrReading)
                    .foregroundStyle(theme.textMuted)
                    .padding(.top, UI.placeholderInset)
                    .padding(.leading, UI.placeholderLeadingInset)
                    .opacity(viewModel.responseText.isEmpty ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel("Your reflection")
            .accessibilityIdentifier("entry.text")
    }

    private var saveBar: some View {
        Button(action: saveEntry) {
            Text("Save entry")
                .frame(maxWidth: .infinity)
        }
        .frmrPrimaryButtonStyle()
        .accessibilityHint("Saves the entry with the photo")
        .accessibilityIdentifier("entry.save")
        .padding(.horizontal, Constants.DesignUI.gutter)
        .padding(.vertical, Constants.DesignUI.Space.s)
        .background(theme.bg)
    }

    private func saveEntry() {
        save(includeText: true)
    }

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
            Haptics.play(.saved)
            camera.endDiaryPrompt()
        }
    }
}

private struct EntryHeaderPhoto: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("Your photo")
        } else {
            Color.appBlack
                .accessibilityHidden(true)
        }
    }
}
