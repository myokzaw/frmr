import SwiftData
import SwiftUI

// v5 F4 / v5.1 F2–F3, F8 editor, shown after every Photo-mode shot and when a
// Roll photo is re-edited. The photo fills the screen; glass icon buttons
// float over its top (Discard, Retake or Delete, Download). Under it sit the
// selected tool's control (one scrubber, or chips for Film and Print), the
// tool icon bar, and the bottom row (Continue to diary, Save to roll). Every
// decision lives in PhotoEditViewModel; this view reports the size the photo
// is drawn at and forwards taps. Always the dark palette: a darkroom around
// the photo.
struct PhotoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale
    @Environment(ErrorState.self) private var errorState

    @Bindable var edit: PhotoEditViewModel
    @State private var isDeleteConfirmationPresented = false
    // Looked up when Delete is tapped, so the dialog can offer the entry choice
    @State private var linkedEntryCount = 0

    private typealias UI = Constants.PhotoEditUI

    var body: some View {
        VStack(spacing: UI.sectionSpacing) {
            photoArea
            toolControl
                .frame(minHeight: UI.toolPanelHeight, alignment: .top)
                .padding(.horizontal, UI.horizontalPadding)
            ToolIconBar(
                items: EditorTool.items,
                selectedID: edit.tool.id,
                modifiedIDs: modifiedToolIDs,
                identifierPrefix: "edit.tool",
                selectedColor: .appAmber,
                idleColor: .appCream,
                onSelect: { edit.tool = EditorTool(id: $0) }
            )
            actionRow
        }
        .padding(.bottom)
        // Chrome text stops growing at the first accessibility size so the
        // photo and the bottom row always fit
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(Color.appBlack.ignoresSafeArea())
        // Dark darkroom: toggles draw for a dark page
        .environment(\.colorScheme, .dark)
        .appErrorAlert(errorState)
        .task { edit.errorState = errorState }
        .confirmationDialog(
            deleteTitle,
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if linkedEntryCount > 0 {
                Button("Delete photo and diary entry", role: .destructive) { deletePhoto(entries: .deleteBoth) }
                    .accessibilityIdentifier("edit.delete.confirmBoth")
                Button("Keep the entry") { deletePhoto(entries: .keepEntry) }
                    .accessibilityIdentifier("edit.delete.keepEntry")
            } else {
                Button("Delete photo", role: .destructive) { deletePhoto(entries: .keepEntry) }
                    .accessibilityIdentifier("edit.delete.confirm")
            }
        }
    }

    private var deleteTitle: String {
        linkedEntryCount > 0
            ? "This photo has a diary entry. Delete it too, or keep the entry with its own copy of the photo?"
            : "Delete this photo from your roll? This can't be undone."
    }

    // MARK: Photo and top bar

    // The renderer must know the drawn size before its first render. The top
    // bar floats over the photo area so the photo can use the whole height.
    private var photoArea: some View {
        GeometryReader { geometry in
            Image(uiImage: edit.displayedPhoto)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .bottomLeading) {
                    RenderingIndicator(isVisible: edit.isRendering || edit.isDevelopingPhoto)
                        .padding(UI.compareBadgePadding)
                }
                .overlay(alignment: .bottomTrailing) {
                    CompareBadge(isVisible: edit.isComparing)
                        .padding(UI.compareBadgePadding)
                }
                .contentShape(Rectangle())
                // Never completes: the pressing callback is the whole gesture
                .onLongPressGesture(
                    minimumDuration: .infinity,
                    maximumDistance: UI.compareMaximumDistance,
                    perform: {},
                    onPressingChanged: edit.setComparing
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Photo")
                .accessibilityValue(edit.isComparing ? "Original" : "With film look")
                .accessibilityHint("Press and hold to see the photo without its film look")
                .accessibilityAction(named: "Compare with original") {
                    edit.setComparing(!edit.isComparing)
                }
                .accessibilityIdentifier("edit.photo")
                .onAppear { edit.setDisplaySize(geometry.size, scale: displayScale) }
                .onChange(of: geometry.size) { _, size in
                    edit.setDisplaySize(size, scale: displayScale)
                }
                .overlay(alignment: .top) { topBar }
        }
    }

    private var topBar: some View {
        HStack(spacing: UI.topBarSpacing) {
            GlassIconButton(
                systemImage: "xmark",
                label: "Discard",
                identifier: "edit.discard",
                rotates: false,
                action: edit.discard
            )
            .accessibilityHint(edit.isReEditing ? "Leaves this photo unchanged" : "Throws this photo away")
            leadingButton
            Text("Hold photo to compare")
                .font(.footnote)
                .foregroundStyle(Color.appCream.opacity(UI.hintOpacity))
                .lineLimit(1)
                .minimumScaleFactor(UI.hintMinScale)
                .frame(maxWidth: .infinity)
                .opacity(edit.didSaveDownload ? 0 : 1)
                .accessibilityHidden(true)
            DownloadControl(
                isSaving: edit.isSavingDownload,
                didSave: edit.didSaveDownload,
                isDisabled: edit.isDownloadDisabled,
                identifier: "edit.download",
                savedIdentifier: "edit.saved",
                action: download
            )
        }
        .padding(.horizontal, UI.topBarPadding)
        .padding(.top, UI.topBarPadding)
    }

    // A fresh shot can be retaken; a Roll photo can be deleted instead
    @ViewBuilder private var leadingButton: some View {
        if edit.isReEditing {
            GlassIconButton(
                systemImage: "trash",
                label: "Delete",
                identifier: "edit.delete",
                rotates: false,
                action: askToDelete
            )
            .accessibilityHint("Removes this photo from your roll after you confirm")
        } else {
            GlassIconButton(
                systemImage: "arrow.counterclockwise",
                label: "Retake",
                identifier: "edit.retake",
                rotates: false,
                action: edit.retake
            )
            .accessibilityHint("Discards this photo and returns to the camera")
        }
    }

    // MARK: Tool control

    @ViewBuilder private var toolControl: some View {
        switch edit.tool {
        case .film: filmChips
        case .print: printControls
        case .effect(let effect): effectScrubber(for: effect)
        }
    }

    private var filmChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UI.chipSpacing) {
                ForEach(edit.stockChoices) { stock in
                    ChoiceChip(
                        label: stock.label,
                        accessibilityLabel: "Film: \(stock.label)",
                        identifier: "edit.stock.\(stock.rawValue)",
                        isSelected: stock == edit.look.stock,
                        selectedColor: .appAmber,
                        selectedForeground: .appBlack,
                        action: { edit.selectStock(stock) }
                    )
                }
            }
        }
    }

    private var printControls: some View {
        VStack(alignment: .leading, spacing: UI.chipSpacing) {
            if edit.isPrintPickerVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: UI.chipSpacing) {
                        ForEach(edit.availablePrints) { printStock in
                            ChoiceChip(
                                label: printStock.label,
                                accessibilityLabel: "Print: \(printStock.label)",
                                identifier: "edit.print.\(printStock.rawValue)",
                                isSelected: printStock == edit.selectedPrint,
                                selectedColor: .appAmber,
                                selectedForeground: .appBlack,
                                action: { edit.selectPrint(printStock) }
                            )
                        }
                    }
                }
            } else {
                Text("This film has no print to choose.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appCream.opacity(UI.hintOpacity))
                    .frame(minHeight: Constants.ReviewUI.stockChipHeight)
            }
            Toggle("Black & white", isOn: Binding(get: { edit.isBlackAndWhiteOn }, set: edit.setBlackAndWhite))
                .disabled(edit.isBlackAndWhiteLocked)
                .font(.subheadline)
                .foregroundStyle(Color.appCream)
                .tint(.appAmber)
                .accessibilityHint("Renders the photo in black and white. Mono films are always black and white.")
                .accessibilityIdentifier("edit.blackAndWhite")
        }
    }

    // One scrubber for all five effects; with no film chosen there is
    // nothing to adjust
    @ViewBuilder private func effectScrubber(for effect: FilmLook.Effect) -> some View {
        if edit.areEffectsAvailable {
            EffectScrubber(
                title: effect.label,
                value: Binding(
                    get: { edit.strength(of: effect) },
                    set: { edit.setStrength($0, for: effect) }
                ),
                defaultValue: effect.defaultStrength,
                hint: effect.toolHint,
                identifier: "edit.scrubber",
                textColor: .appCream,
                tint: .appAmber
            )
        } else {
            Text("Pick a film to adjust its effects.")
                .font(.subheadline)
                .foregroundStyle(Color.appCream.opacity(UI.hintOpacity))
                .frame(maxWidth: .infinity, minHeight: Constants.ReviewUI.stockChipHeight, alignment: .leading)
        }
    }

    // A dot under each effect whose value is off the stock default
    private var modifiedToolIDs: Set<String> {
        Set(FilmLook.Effect.allCases
            .filter { edit.strength(of: $0) != $0.defaultStrength }
            .map(\.rawValue))
    }

    // MARK: Actions

    // Continue to diary (secondary, only right after a capture) and Save to
    // roll (primary), side by side
    private var actionRow: some View {
        HStack(spacing: UI.actionSpacing) {
            if edit.canContinueToDiary {
                Button(action: continueToDiary) {
                    Text("Continue to diary")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appCream)
                        .lineLimit(1)
                        .minimumScaleFactor(UI.hintMinScale)
                        .frame(maxWidth: .infinity, minHeight: UI.actionButtonHeight)
                        .frmrGlass(in: RoundedRectangle(cornerRadius: UI.actionButtonCornerRadius))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Saves the photo to your roll, then lets you write about it")
                .accessibilityIdentifier("edit.continueDiary")
            }

            Button(action: save) {
                ZStack {
                    Text(edit.isReEditing ? "Save" : "Save to roll")
                        .opacity(edit.isSavingToRoll ? 0 : 1)
                    ProgressView().tint(.appBlack)
                        .opacity(edit.isSavingToRoll ? 1 : 0)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appBlack)
                .frame(maxWidth: .infinity, minHeight: UI.actionButtonHeight)
                .background(Color.appAmber, in: RoundedRectangle(cornerRadius: UI.actionButtonCornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(edit.isSavingToRoll)
            .accessibilityLabel(edit.isReEditing ? "Save" : "Save to roll")
            .accessibilityHint("Keeps this photo and its film look in your roll")
            .accessibilityIdentifier("edit.save")
        }
        .padding(.horizontal, UI.horizontalPadding)
    }

    private func save() {
        Task { await edit.saveToRoll(context: modelContext) }
    }

    private func continueToDiary() {
        Task { await edit.continueToDiary(context: modelContext) }
    }

    private func download() {
        Task { await edit.download() }
    }

    private func askToDelete() {
        linkedEntryCount = edit.linkedEntryCount(in: modelContext)
        isDeleteConfirmationPresented = true
    }

    private func deletePhoto(entries: RollViewModel.RollDeletion) {
        _ = edit.deleteFromRoll(entries: entries, context: modelContext)
    }
}

// What the tool icon bar offers, in order: Film, Print, then the five
// effects. The selection lives in the view model (`PhotoEditViewModel.tool`).
private typealias EditorTool = PhotoEditViewModel.Tool

private extension PhotoEditViewModel.Tool {
    static let items: [ToolIconItem] = [
        ToolIconItem(id: "film", title: "Film", systemImage: "film", hint: "Choose the film stock"),
        ToolIconItem(id: "print", title: "Print", systemImage: "printer", hint: "Choose the print and black and white"),
    ] + FilmLook.Effect.allCases.map {
        ToolIconItem(id: $0.rawValue, title: $0.label, systemImage: $0.toolSymbolName, hint: $0.toolHint)
    }
}

extension FilmLook.Effect {
    /// What the effect does, for the tool bar's and scrubber's VoiceOver hint.
    var toolHint: String {
        switch self {
        case .halation: return "Warm glow around bright highlights"
        case .haze: return "Softens and spreads bright areas"
        case .lightLeak: return "A streak of light at the frame edge"
        case .grain: return "How much film grain shows"
        case .vignette: return "Darkens the corners of the frame"
        }
    }

    /// The tool bar's glyph for this effect.
    var toolSymbolName: String {
        switch self {
        case .halation: return "sun.max"
        case .haze: return "cloud.fog"
        case .lightLeak: return "rays"
        case .grain: return "circle.dotted"
        case .vignette: return "circle.dashed.inset.filled"
        }
    }
}

// Shown while the photo is held: the picture on screen is the original
private struct CompareBadge: View {
    let isVisible: Bool

    var body: some View {
        Text("Original")
            .font(.system(size: Constants.ReviewUI.savedFontSize, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Constants.ReviewUI.savedHorizontalPadding)
            .padding(.vertical, Constants.ReviewUI.savedVerticalPadding)
            .frmrGlassCapsule()
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: Constants.PhotoEditUI.animationDuration), value: isVisible)
            .accessibilityHidden(true)
            .accessibilityIdentifier("edit.compareBadge")
    }
}
