import SwiftData
import SwiftUI
import TipKit

// v5 F4 / v5.1 F2–F3, F8 / v5.2 M5 editor, shown after a Photo shot and
// when a Roll photo is re-edited. The photo fills the screen; two glass
// groups float over its top ([Discard, Retake or Delete] and [Compare,
// Download], research §4.5). Under it sit the selected tool's control (the
// Exposure or effect scrubber, or a row of this photo in each film or
// print), the tool bar with value rings, and the bottom row (Continue to
// diary, Save to roll). Every decision lives in PhotoEditViewModel; this
// view reports sizes and forwards taps. Always the darkroom palette.
struct PhotoEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState

    @Bindable var edit: PhotoEditViewModel
    @State private var isDeleteConfirmationPresented = false
    // Looked up when Delete is tapped; nil = couldn't be read, so ask both ways
    @State private var linkedEntryCount: Int?

    private let diaryTip = DiaryTip()
    private typealias UI = Constants.PhotoEditUI
    private var theme: ThemePalette { ThemePalette.resolve(for: .dark, surface: .darkroom, contrast: contrast) }

    var body: some View {
        VStack(spacing: UI.sectionSpacing) {
            photoArea
            toolControl
                .frame(minHeight: UI.toolPanelHeight, alignment: .top)
            ToolIconBar(
                items: Self.toolItems(look: edit.look, exposureReadout: edit.exposureReadout),
                selectedID: edit.tool.id,
                identifierPrefix: "edit.tool",
                selectedColor: theme.accentFill,
                idleColor: theme.text,
                onSelect: { edit.tool = PhotoEditViewModel.Tool(id: $0) }
            )
            actionRow
        }
        .padding(.bottom, Constants.DesignUI.Space.s)
        // Chrome text stops growing at the first accessibility size so the
        // photo and the bottom row always fit
        .frmrChromeTypeSize()
        .background(theme.bg.ignoresSafeArea())
        // Darkroom: toggles, sheets and the status bar draw for a dark page
        .environment(\.colorScheme, .dark)
        .frmrDarkroomStatusBar()
        .appErrorAlert(errorState)
        .task {
            edit.errorState = errorState
            edit.loadLinkedEntryCount(context: modelContext)
        }
        .sensoryFeedback(.warning, trigger: isDeleteConfirmationPresented) { _, shown in shown }
        .confirmationDialog(
            RollPromptText.deleteTitle(photoCount: 1, linkedEntries: linkedEntryCount),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            if RollPromptText.asksAboutEntries(linkedEntryCount) {
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

    // MARK: Photo and top bar

    // The renderer must know the drawn size before its first render. The top
    // bar floats over the photo area so the photo can use the whole height.
    private var photoArea: some View {
        GeometryReader { geometry in
            DevelopingPhoto(image: edit.displayedPhoto, isDeveloping: edit.isDevelopingPhoto)
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
                .accessibilityAction(named: "Show original") { edit.setComparing(!edit.isComparing) }
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
            FrmrGlassContainer(spacing: UI.topBarSpacing) {
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
                }
            }
            Spacer(minLength: 0)
            FrmrGlassContainer(spacing: UI.topBarSpacing) {
                HStack(spacing: UI.topBarSpacing) {
                    GlassIconButton(
                        systemImage: "square.split.2x1",
                        label: "Compare",
                        identifier: "edit.compare",
                        value: edit.isComparing ? "Showing original" : "Showing film look",
                        foreground: edit.isComparing ? theme.accentFill : .white,
                        rotates: false,
                        action: { edit.setComparing(!edit.isComparing) }
                    )
                    .accessibilityHint("Switches between the photo with and without its film look. You can also hold the photo.")
                    DownloadControl(
                        isSaving: edit.isSavingDownload,
                        didSave: edit.didSaveDownload,
                        isDisabled: edit.isDownloadDisabled,
                        identifier: "edit.download",
                        savedIdentifier: "edit.saved",
                        action: download
                    )
                }
            }
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
        case .exposure: exposureScrubber
        case .film: filmPreviews
        case .print: printControls
        case .effect(let effect): effectScrubber(for: effect)
        }
    }

    // v5.2 F-EXP: −2…+2 EV in ⅓ stops, firm tick at 0
    private var exposureScrubber: some View {
        EffectScrubber(
            title: "Exposure",
            value: Binding(get: { edit.exposure }, set: edit.setExposure),
            defaultValue: 0,
            hint: "Over- or under-exposes the film, in thirds of a stop",
            identifier: "edit.exposure",
            textColor: theme.text,
            tint: theme.accentFill,
            scale: .exposure,
            valueText: edit.exposureReadout,
            resetHint: "Returns to 0 EV"
        )
        .padding(.horizontal, UI.horizontalPadding)
    }

    // v5.2 M5: this photo in each stock, Photos-style
    private var filmPreviews: some View {
        PreviewRow(
            choices: edit.stockChoices,
            selected: edit.look.stock,
            image: { edit.stockPreviews[$0] },
            code: { $0.shortCode },
            label: { "Film: \($0.label)" },
            identifier: { "edit.stock.\($0.rawValue)" },
            ringColor: theme.accentFill,
            textColor: theme.text,
            onSelect: edit.selectStock
        )
        .task(id: edit.look) { requestPreviews() }
    }

    private var printControls: some View {
        VStack(alignment: .leading, spacing: Constants.DesignUI.Space.s) {
            if edit.isPrintPickerVisible {
                PreviewRow(
                    choices: edit.availablePrints,
                    selected: edit.selectedPrint,
                    image: { edit.printPreviews[$0] },
                    code: { $0.label },
                    label: { "Print: \($0.label)" },
                    identifier: { "edit.print.\($0.rawValue)" },
                    ringColor: theme.accentFill,
                    textColor: theme.text,
                    onSelect: { edit.selectPrint($0) }
                )
                .task(id: edit.look) { requestPreviews() }
            } else {
                Text("This film has no print to choose.")
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
                    .frame(minHeight: Constants.DesignUI.targetMin)
                    .padding(.horizontal, UI.horizontalPadding)
            }
            Toggle("Black & white", isOn: Binding(get: { edit.isBlackAndWhiteOn }, set: edit.setBlackAndWhite))
                .disabled(edit.isBlackAndWhiteLocked)
                .font(.frmrLabel)
                .foregroundStyle(theme.text)
                .tint(theme.accentFill)
                .accessibilityHint("Renders the photo in black and white. Mono films are always black and white.")
                .accessibilityIdentifier("edit.blackAndWhite")
                .padding(.horizontal, UI.horizontalPadding)
        }
    }

    // One scrubber for all five effects; with no film chosen there is
    // nothing to adjust
    private func effectScrubber(for effect: FilmLook.Effect) -> some View {
        Group {
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
                    textColor: theme.text,
                    tint: theme.accentFill
                )
            } else {
                Text("Pick a film to adjust its effects.")
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: Constants.DesignUI.targetMin, alignment: .leading)
            }
        }
        .padding(.horizontal, UI.horizontalPadding)
    }

    private func requestPreviews() {
        edit.requestPreviews(size: CGSize(width: UI.previewWidth, height: UI.previewHeight), scale: displayScale)
    }

    // MARK: Actions

    // Continue to diary (secondary glass, only right after a capture) and
    // Save to roll (the one amber primary), side by side
    private var actionRow: some View {
        HStack(spacing: UI.actionSpacing) {
            if edit.canContinueToDiary {
                Button(action: continueToDiary) {
                    Text("Continue to diary")
                        .font(.frmrLabel)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: Constants.DesignUI.buttonPrimaryHeight)
                        .frmrGlassCapsule(interactive: true)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .popoverTip(diaryTip)
                .accessibilityHint("Saves the photo to your roll, then lets you write about it")
                .accessibilityIdentifier("edit.continueDiary")
            }

            Button(action: save) {
                ZStack {
                    Text(edit.isReEditing ? "Save" : "Save to roll")
                        .opacity(edit.isSavingToRoll ? 0 : 1)
                    ProgressView().tint(theme.onAccent)
                        .opacity(edit.isSavingToRoll ? 1 : 0)
                }
                .font(.frmrLabel)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .frmrPrimaryButtonStyle()
            .disabled(edit.isSavingToRoll)
            .accessibilityLabel(edit.isReEditing ? "Save" : "Save to roll")
            .accessibilityHint("Keeps this photo and its film look in your roll")
            .accessibilityIdentifier("edit.save")
        }
        .padding(.horizontal, UI.horizontalPadding)
    }

    private func save() {
        Task {
            if await edit.saveToRoll(context: modelContext) {
                Haptics.play(.saved)
                FrmrTips.notePhotoSaved()
            }
        }
    }

    private func continueToDiary() {
        diaryTip.invalidate(reason: .actionPerformed)
        Task {
            if await edit.continueToDiary(context: modelContext) {
                FrmrTips.notePhotoSaved()
            }
        }
    }

    private func download() {
        Task { await edit.download() }
    }

    private func askToDelete() {
        linkedEntryCount = edit.linkedEntryCountIfKnown(in: modelContext)
        isDeleteConfirmationPresented = true
    }

    private func deletePhoto(entries: RollViewModel.RollDeletion) {
        _ = edit.deleteFromRoll(entries: entries, context: modelContext)
    }
}

// MARK: Tool bar items

extension PhotoEditView {
    /// What the tool bar offers, in order (Exposure, Film, Print, then the
    /// five effects), each with its VoiceOver value and value ring. Pure, so
    /// the rings are unit-testable (replaces the v5.1 modified-tools set).
    nonisolated static func toolItems(look: FilmLook, exposureReadout: String) -> [ToolIconItem] {
        let effects = look.stock.hasEffects
        let fixed = [
            ToolIconItem(
                id: "exposure", title: "Exposure", systemImage: "plus.forwardslash.minus",
                hint: "Over- or under-expose the film", value: exposureReadout,
                ring: ToolRing.fraction(exposure: look.exposure)
            ),
            ToolIconItem(id: "film", title: "Film", systemImage: "film", hint: "Choose the film stock", value: look.stock.label),
            ToolIconItem(
                id: "print", title: "Print", systemImage: "printer",
                hint: "Choose the print and black and white", value: look.resolvedPrint?.label ?? ""
            ),
        ]
        return fixed + FilmLook.Effect.allCases.map { effect in
            let strength = look.strengths[effect]
            return ToolIconItem(
                id: effect.rawValue, title: effect.label, systemImage: effect.toolSymbolName, hint: effect.toolHint,
                value: effects ? ScrubberMath.percentText(strength, scale: Constants.ScrubberUI.percentScale) : "Off",
                ring: effects ? ToolRing.fraction(strength: strength) : nil
            )
        }
    }
}

extension FilmLook.Effect {
    /// What the effect does, for the tool bar's and scrubber's VoiceOver hint.
    nonisolated var toolHint: String {
        switch self {
        case .halation: return "Warm glow around bright highlights"
        case .haze: return "Softens and spreads bright areas"
        case .lightLeak: return "A streak of light at the frame edge"
        case .grain: return "How much film grain shows"
        case .vignette: return "Darkens the corners of the frame"
        }
    }

    /// The tool bar's glyph for this effect.
    nonisolated var toolSymbolName: String {
        switch self {
        case .halation: return "sun.max"
        case .haze: return "cloud.fog"
        case .lightLeak: return "rays"
        case .grain: return "circle.dotted"
        case .vignette: return "circle.dashed.inset.filled"
        }
    }
}

// MARK: Pieces

// v5.2 C2: until the RAW develops, the JPEG preview reads "latent" (lower
// saturation and contrast, softened) and resolves when it lands. It plays
// only during the real wait; under Reduce Motion it just changes.
private struct DevelopingPhoto: View {
    let image: UIImage
    let isDeveloping: Bool

    private typealias UI = Constants.PhotoEditUI

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .saturation(isDeveloping ? UI.latentSaturation : 1)
            .contrast(isDeveloping ? UI.latentContrast : 1)
            .blur(radius: isDeveloping ? UI.latentBlur : 0)
            .frmrAnimation(.develop, value: isDeveloping)
    }
}

// Shown while comparing: the picture on screen is the original
private struct CompareBadge: View {
    let isVisible: Bool

    var body: some View {
        if isVisible {
            Text("Original")
                .font(.frmrMeta.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Constants.DesignUI.Space.m)
                .padding(.vertical, Constants.DesignUI.Space.xs)
                .frmrGlassCapsule()
                .accessibilityHidden(true)
                .accessibilityIdentifier("edit.compareBadge")
        }
    }
}
