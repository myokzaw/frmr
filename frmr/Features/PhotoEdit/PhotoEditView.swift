import SwiftData
import SwiftUI

// v5 F4 edit step: shown after every Photo-mode shot and when a Roll photo
// is re-edited. Top bar (Retake or Delete, the compare hint, Download), the
// photo, Film / Print / Effects tabs, then Discard and Save to roll. Every
// decision lives in PhotoEditViewModel; this view reports the size the photo
// is drawn at and forwards taps. Always the dark palette: a darkroom around
// the photo, like the diary review.
struct PhotoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale
    @Environment(ErrorState.self) private var errorState

    @Bindable var edit: PhotoEditViewModel
    @State private var isDeleteConfirmationPresented = false

    private var theme: ThemePalette { ThemePalette.resolve(for: .dark) }

    var body: some View {
        VStack(spacing: Constants.PhotoEditUI.sectionSpacing) {
            topBar
            photoArea
            toolTabs
            toolPanel
                .frame(height: Constants.PhotoEditUI.toolPanelHeight, alignment: .top)
            actionRow
        }
        .padding(.bottom)
        .background(Color.appBlack.ignoresSafeArea())
        // Dark darkroom: slider tracks and toggles draw for a dark page
        .environment(\.colorScheme, .dark)
        .appErrorAlert(errorState)
        .task { edit.errorState = errorState }
        .confirmationDialog(
            "Delete this photo from your roll? This can't be undone.",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete photo", role: .destructive, action: deletePhoto)
                .accessibilityIdentifier("edit.delete.confirm")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: Constants.PhotoEditUI.topBarSpacing) {
            leadingButton
            Text("Hold photo to compare")
                .font(.footnote)
                .foregroundStyle(Color.appCream.opacity(Constants.PhotoEditUI.hintOpacity))
                .lineLimit(1)
                .minimumScaleFactor(Constants.PhotoEditUI.hintMinScale)
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
        .padding(.horizontal)
        .frame(minHeight: Constants.PhotoEditUI.topBarHeight)
    }

    // A fresh shot can be retaken; a Roll photo can be deleted instead
    @ViewBuilder private var leadingButton: some View {
        if edit.isReEditing {
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appCream)
                    .frame(minHeight: Constants.ReviewUI.stockChipHeight)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Removes this photo from your roll after you confirm")
            .accessibilityIdentifier("edit.delete")
        } else {
            Button(action: edit.retake) {
                Text("Retake")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appCream)
                    .frame(minHeight: Constants.ReviewUI.stockChipHeight)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Discards this photo and returns to the camera")
            .accessibilityIdentifier("edit.retake")
        }
    }

    // MARK: Photo

    // The renderer must know the drawn size before its first render
    private var photoArea: some View {
        GeometryReader { geometry in
            Image(uiImage: edit.displayedPhoto)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .overlay(alignment: .bottomLeading) {
                    RenderingIndicator(isVisible: edit.isRendering || edit.isDevelopingPhoto)
                        .padding(Constants.PhotoEditUI.compareBadgePadding)
                }
                .overlay(alignment: .topLeading) {
                    CompareBadge(isVisible: edit.isComparing)
                        .padding(Constants.PhotoEditUI.compareBadgePadding)
                }
                .contentShape(Rectangle())
                // Never completes: the pressing callback is the whole gesture
                .onLongPressGesture(
                    minimumDuration: .infinity,
                    maximumDistance: Constants.PhotoEditUI.compareMaximumDistance,
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
        }
    }

    // MARK: Tools

    private var toolTabs: some View {
        HStack(spacing: 0) {
            EditTab(label: "Film", identifier: "edit.tab.film", isActive: edit.tool == .film, color: theme.primary) {
                edit.tool = .film
            }
            EditTab(label: "Print", identifier: "edit.tab.print", isActive: edit.tool == .print, color: theme.primary) {
                edit.tool = .print
            }
            EditTab(label: "Effects", identifier: "edit.tab.effects", isActive: edit.tool == .effects, color: theme.primary) {
                edit.tool = .effects
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var toolPanel: some View {
        switch edit.tool {
        case .film: filmPanel
        case .print: printPanel
        case .effects: effectsPanel
        }
    }

    private var chipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: Constants.PhotoEditUI.chipColumnMinimum), spacing: Constants.ReviewUI.stockChipSpacing)]
    }

    private var filmPanel: some View {
        ScrollView {
            LazyVGrid(columns: chipColumns, spacing: Constants.ReviewUI.stockChipSpacing) {
                ForEach(edit.stockChoices) { stock in
                    ChoiceChip(
                        label: stock.label,
                        accessibilityLabel: "Film: \(stock.label)",
                        identifier: "edit.stock.\(stock.rawValue)",
                        isSelected: stock == edit.look.stock,
                        selectedColor: theme.primary,
                        action: { edit.selectStock(stock) }
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    private var printPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.PhotoEditUI.sectionSpacing) {
                if edit.isPrintPickerVisible {
                    LazyVGrid(columns: chipColumns, spacing: Constants.ReviewUI.stockChipSpacing) {
                        ForEach(edit.availablePrints) { printStock in
                            ChoiceChip(
                                label: printStock.label,
                                accessibilityLabel: "Print: \(printStock.label)",
                                identifier: "edit.print.\(printStock.rawValue)",
                                isSelected: printStock == edit.selectedPrint,
                                selectedColor: theme.primary,
                                action: { edit.selectPrint(printStock) }
                            )
                        }
                    }
                } else {
                    Text("This film has no print to choose.")
                        .font(.subheadline)
                        .foregroundStyle(Color.appCream.opacity(Constants.PhotoEditUI.hintOpacity))
                }
                Toggle("Black & white", isOn: Binding(get: { edit.isBlackAndWhiteOn }, set: edit.setBlackAndWhite))
                    .disabled(edit.isBlackAndWhiteLocked)
                    .foregroundStyle(Color.appCream)
                    .tint(theme.primary)
                    .accessibilityHint("Renders the photo in black and white. Mono films are always black and white.")
                    .accessibilityIdentifier("edit.blackAndWhite")
            }
            .padding(.horizontal)
        }
    }

    private var effectsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Effects")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Color.appCream.opacity(Constants.PhotoEditUI.hintOpacity))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // OPEN: v5-5 — Reset lives in the Effects header
                Button("Reset", action: edit.resetToStockDefaults)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appCream)
                    .disabled(!edit.canResetToStockDefaults)
                    .opacity(edit.canResetToStockDefaults ? 1 : Constants.CameraUI.disabledControlOpacity)
                    .accessibilityHint("Restores this film's own print and effect strengths")
                    .accessibilityIdentifier("edit.effects.reset")
            }
            .padding(.horizontal)
            if edit.areEffectsAvailable {
                ScrollView {
                    EffectSliders(
                        strength: { edit.strength(of: $0) },
                        setStrength: { edit.setStrength($0, for: $1) },
                        identifierPrefix: "edit.slider",
                        textColor: Color.appCream,
                        tint: theme.primary
                    )
                    .padding(.horizontal)
                }
            } else {
                Text("Pick a film to adjust its effects.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appCream.opacity(Constants.PhotoEditUI.hintOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    // MARK: Actions

    // Discard bottom left (secondary), Save to roll bottom right (primary)
    private var actionRow: some View {
        HStack(spacing: Constants.ReviewUI.sectionSpacing) {
            Button(action: edit.discard) {
                Text("Discard")
                    .font(.system(size: Constants.EditorUI.entryFontSize, weight: .semibold))
                    .foregroundStyle(Color.appCream)
                    .frame(maxWidth: .infinity, minHeight: Constants.PhotoEditUI.actionButtonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius)
                            .strokeBorder(theme.cardBorder)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint(edit.isReEditing ? "Leaves this photo unchanged" : "Throws this photo away")
            .accessibilityIdentifier("edit.discard")

            Button(action: save) {
                ZStack {
                    Text(edit.isReEditing ? "Save" : "Save to roll")
                        .opacity(edit.isSavingToRoll ? 0 : 1)
                    ProgressView().tint(.white)
                        .opacity(edit.isSavingToRoll ? 1 : 0)
                }
                .font(.system(size: Constants.EditorUI.entryFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: Constants.PhotoEditUI.actionButtonHeight)
                .background(theme.primary, in: RoundedRectangle(cornerRadius: Constants.EditorUI.buttonCornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(edit.isSavingToRoll)
            .accessibilityLabel(edit.isReEditing ? "Save" : "Save to roll")
            .accessibilityHint("Keeps this photo and its film look in your roll")
            .accessibilityIdentifier("edit.save")
        }
        .padding(.horizontal)
    }

    private func save() {
        Task { await edit.saveToRoll(context: modelContext) }
    }

    private func download() {
        Task { await edit.download() }
    }

    private func deletePhoto() {
        _ = edit.deleteFromRoll(context: modelContext)
    }
}

private struct EditTab: View {
    let label: String
    let identifier: String
    let isActive: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? color : Color.appCream.opacity(Constants.PhotoEditUI.hintOpacity))
                .frame(maxWidth: .infinity, minHeight: Constants.PhotoEditUI.tabHeight)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? color : .clear)
                        .frame(height: Constants.PhotoEditUI.tabUnderlineHeight)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
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
            .background(.black.opacity(Constants.ReviewUI.overlayOpacity), in: Capsule())
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: Constants.PhotoEditUI.animationDuration), value: isVisible)
            .accessibilityHidden(true)
            .accessibilityIdentifier("edit.compareBadge")
    }
}
