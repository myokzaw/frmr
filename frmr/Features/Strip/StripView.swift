import SwiftData
import SwiftUI

// Strip preview + customisation (project.md §2, screen 4; v5.1 F10; v5.2
// S3). The strip is the hero on the darkroom, fitted above the controls so
// nothing sits on it. Two glass groups float at the top: Close on the left,
// [Share, Download] on the right. Under the strip sit the photo editor's
// controls (no sheet): a tool bar
// (Paper, Film, Print, the five effects), the selected tool's control
// and the one primary, "Keep strip" (v5.2-7: Save and Archive merged; it
// keeps the strip in the Library). Presented after Film strip mode or from
// the Library.
struct StripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState

    @State private var viewModel: StripViewModel
    @State private var tool: StripTool = .paper
    @State private var isDownloading = false
    private let onDone: () -> Void

    private typealias UI = Constants.StripUI

    init(items: [StripItem], isPhotobooth: Bool, onDone: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: StripViewModel(items: items, isPhotobooth: isPhotobooth))
        self.onDone = onDone
    }

    private var theme: ThemePalette { ThemePalette.resolve(for: .dark, surface: .darkroom, contrast: contrast) }

    private var shareImages: [Image] {
        viewModel.stripImages.map { Image(uiImage: $0) }
    }

    // A tool can disappear under the selection (Off hides the effects);
    // Paper is always there to fall back on
    private var availableTools: [StripTool] {
        var tools: [StripTool] = [.paper, .film, .print]
        if viewModel.areEffectsVisible { tools += FilmLook.Effect.allCases.map(StripTool.effect) }
        return tools
    }

    private var activeTool: StripTool {
        availableTools.contains(tool) ? tool : .paper
    }

    var body: some View {
        VStack(spacing: UI.sheetSpacing) {
            stripPreviews
                .safeAreaPadding(.top, UI.heroTopInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { topBar }
            toolControl
                .frame(minHeight: UI.toolPanelHeight, alignment: .top)
            ToolIconBar(
                items: availableTools.map { $0.item(strengths: viewModel.customization.strengths, effectsOn: viewModel.areEffectsVisible) },
                selectedID: activeTool.id,
                identifierPrefix: "strip.tool",
                selectedColor: theme.accentFill,
                idleColor: theme.text,
                onSelect: { tool = StripTool(id: $0) }
            )
            Button(action: keepStrip) {
                Text("Keep strip")
                    .frame(maxWidth: .infinity)
            }
            .frmrPrimaryButtonStyle()
            .disabled(viewModel.areActionsDisabled)
            .accessibilityHint("Keeps the strip in your library")
            .accessibilityIdentifier("strip.keep")
            .padding(.horizontal, UI.sheetPadding)
        }
        .padding(.bottom, Constants.DesignUI.Space.s)
        .foregroundStyle(theme.text)
        .tint(theme.accentFill)
        // Chrome text stops growing at the first accessibility size so
        // Keep strip never leaves the screen
        .frmrChromeTypeSize()
        .background(theme.bg.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .frmrDarkroomStatusBar()
        .appErrorAlert(errorState)
        .task {
            viewModel.errorState = errorState
            await viewModel.renderStrips()
        }
        .onChange(of: viewModel.customization) {
            Task { await viewModel.renderStrips() }
        }
    }

    // MARK: Top glass groups

    private var topBar: some View {
        HStack {
            GlassIconButton(
                systemImage: "xmark",
                label: "Close",
                identifier: "strip.close",
                rotates: false,
                action: close
            )
            Spacer()
            FrmrGlassContainer(spacing: Constants.DesignUI.Space.s) {
                HStack(spacing: Constants.DesignUI.Space.s) {
                    ShareLink(items: shareImages) { _ in
                        SharePreview("Film strip")
                    } label: {
                        GlassIconGlyph(systemImage: "square.and.arrow.up", rotates: false)
                    }
                    .accessibilityLabel("Share")
                    .accessibilityIdentifier("strip.share")
                    // The editor's Download: spinner, then a "Saved" badge
                    DownloadControl(
                        isSaving: isDownloading,
                        didSave: viewModel.didSaveToCameraRoll,
                        isDisabled: isDownloading,
                        identifier: "strip.download",
                        savedIdentifier: "strip.saved",
                        label: "Download strip",
                        hint: "Saves the strip to your photo library",
                        action: download
                    )
                }
            }
            .disabled(viewModel.areActionsDisabled)
            .opacity(viewModel.areActionsDisabled ? Constants.CameraUI.disabledControlOpacity : 1)
        }
        .padding(.horizontal, Constants.DesignUI.gutter)
        .padding(.top, UI.topBarPadding)
    }

    // MARK: Hero

    private var stripPreviews: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: UI.previewSpacing) {
                    ForEach(Array(viewModel.stripImages.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: geometry.size.height)
                            .shadow(
                                color: .black.opacity(UI.previewShadowOpacity),
                                radius: UI.previewShadowRadius / 2
                            )
                            .accessibilityLabel("Strip preview")
                            .accessibilityIdentifier("strip.preview")
                    }
                }
                .padding(.horizontal, UI.previewHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .overlay {
                if viewModel.stripImages.isEmpty {
                    ProgressView().tint(.white)
                }
            }
        }
    }

    // MARK: Tool control

    @ViewBuilder private var toolControl: some View {
        switch activeTool {
        case .paper: paperControl
        case .film: filmPreviews
        case .print: printControls
        case .effect(let effect): effectScrubber(for: effect)
        }
    }

    // v4 F8: white and black only, each labelled
    private var paperControl: some View {
        HStack(spacing: UI.paperSpacing) {
            ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { option in
                PaperThumb(
                    color: option.color,
                    label: option.label,
                    identifier: "strip.background.\(option.settingsName)",
                    isSelected: option == viewModel.customization.background,
                    ringColor: theme.accentFill,
                    rimColor: theme.cardBorder,
                    textColor: theme.text,
                    action: { viewModel.customization.background = option }
                )
            }
        }
        .padding(.horizontal, UI.sheetPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // nil = As shot: every frame keeps the stock it was taken on
    private var filmPreviews: some View {
        PreviewRow(
            choices: StripCustomization.stockChoices,
            selected: .some(viewModel.customization.filmStock),
            image: { $0.map { viewModel.stockPreviews[$0] } ?? viewModel.asShotPreview },
            code: { $0?.shortCode ?? UI.asShotCode },
            label: { "Film: \(StripCustomization.label(forStockChoice: $0))" },
            identifier: { "strip.stock.\($0?.rawValue ?? "asShot")" },
            ringColor: theme.accentFill,
            textColor: theme.text,
            onSelect: { viewModel.customization.filmStock = $0 }
        )
        .task(id: viewModel.customization) { requestPreviews() }
    }

    private var printControls: some View {
        VStack(alignment: .leading, spacing: Constants.DesignUI.Space.s) {
            if viewModel.isPrintPickerVisible {
            PreviewRow(
                choices: viewModel.availablePrints,
                selected: viewModel.selectedPrint,
                image: { viewModel.printPreviews[$0] },
                code: { $0.label },
                label: { "Print: \($0.label)" },
                identifier: { "strip.print.\($0.rawValue)" },
                ringColor: theme.accentFill,
                textColor: theme.text,
                onSelect: { viewModel.selectedPrint = $0 }
            )
            .task(id: viewModel.customization) { requestPreviews() }
            } else {
                Text("This film has no print to choose.")
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
                    .frame(minHeight: Constants.DesignUI.targetMin)
                    .padding(.horizontal, UI.sheetPadding)
            }
            Toggle("Black & white", isOn: $viewModel.blackAndWhiteToggle)
                .disabled(viewModel.isBlackAndWhiteLocked)
                .font(.frmrLabel)
                .foregroundStyle(theme.text)
                .tint(theme.accentFill)
                .accessibilityHint("Renders the strip in black and white. Mono stocks are always black and white.")
                .accessibilityIdentifier("strip.blackAndWhite")
                .padding(.horizontal, UI.sheetPadding)
        }
    }

    private func requestPreviews() {
        viewModel.requestPreviews(size: CGSize(width: UI.previewThumbWidth, height: UI.previewThumbHeight), scale: displayScale)
    }

    // v5 F5: strength replaces the v4 on/off toggles. 100% is the v4
    // strength of an effect that was on; the scrubber reaches 150%.
    private func effectScrubber(for effect: FilmLook.Effect) -> some View {
        EffectScrubber(
            title: effect.label,
            value: Binding(
                get: { viewModel.customization.strengths[effect] },
                set: { viewModel.customization.strengths[effect] = $0 }
            ),
            defaultValue: effect.defaultStrength,
            hint: effect.toolHint,
            identifier: "strip.scrubber",
            textColor: theme.text,
            tint: theme.accentFill
        )
        .padding(.horizontal, UI.sheetPadding)
    }

    // MARK: Actions

    // OPEN: archive behaviour (project.md §13 #6) — v5.2-7 default: one
    // "Keep strip" keeps it in the in-app library; Download exports it
    private func keepStrip() {
        if viewModel.persist(context: modelContext) {
            Haptics.play(.saved)
            close()
        }
    }

    private func download() {
        isDownloading = true
        Task {
            await viewModel.saveToCameraRoll()
            isDownloading = false
        }
    }

    private func close() {
        onDone()
        dismiss()
    }
}

// What the tool bar offers, in order. The selection is view state: the view
// model only cares about the customisation it produces.
private enum StripTool: Hashable {
    case paper
    case film
    case print
    case effect(FilmLook.Effect)

    init(id: String) {
        switch id {
        case "paper": self = .paper
        case "film": self = .film
        case "print": self = .print
        default: self = FilmLook.Effect(rawValue: id).map(StripTool.effect) ?? .paper
        }
    }

    var id: String {
        switch self {
        case .paper: return "paper"
        case .film: return "film"
        case .print: return "print"
        case .effect(let effect): return effect.rawValue
        }
    }

    func item(strengths: FilmLook.Strengths, effectsOn: Bool) -> ToolIconItem {
        switch self {
        case .paper:
            return ToolIconItem(id: id, title: "Paper", systemImage: "square.fill.on.square.fill", hint: "Choose the strip's paper colour")
        case .film:
            return ToolIconItem(id: id, title: "Film", systemImage: "film", hint: "Choose the film the strip is rendered on")
        case .print:
            return ToolIconItem(id: id, title: "Print", systemImage: "printer", hint: "Choose the paper the film is printed on")
        case .effect(let effect):
            let strength = strengths[effect]
            return ToolIconItem(
                id: id, title: effect.label, systemImage: effect.toolSymbolName, hint: effect.toolHint,
                value: ScrubberMath.percentText(strength, scale: Constants.ScrubberUI.percentScale),
                ring: effectsOn ? ToolRing.fraction(strength: strength) : nil
            )
        }
    }
}

/// A paper colour as one of the editor's rounded preview thumbs.
private struct PaperThumb: View {
    let color: Color
    let label: String
    let identifier: String
    let isSelected: Bool
    let ringColor: Color
    let rimColor: Color
    let textColor: Color
    let action: () -> Void

    private typealias UI = Constants.StripUI
    private typealias EditUI = Constants.PhotoEditUI
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: EditUI.previewLabelSpacing) {
                color
                    .frame(width: UI.previewThumbWidth, height: UI.previewThumbHeight)
                    .clipShape(shape)
                    // A hairline rim keeps the swatch that matches the page visible
                    .overlay { shape.strokeBorder(rimColor, lineWidth: UI.swatchRimWidth) }
                    .overlay { shape.strokeBorder(isSelected ? ringColor : .clear, lineWidth: EditUI.previewRingWidth) }
                Text(label)
                    .frmrCodeStyle()
                    .foregroundStyle(isSelected ? ringColor : textColor)
            }
            .frame(minWidth: UI.swatchTapTarget, minHeight: UI.swatchTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paper, \(label.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
