import SwiftData
import SwiftUI

// Strip preview + customisation (project.md §2, screen 4; v5.1 F10; v5.2
// S3). The strip is the hero on the darkroom, fitted above the controls so
// nothing sits on it. Two glass groups float at the top: Close on the left,
// [Share, Download] on the right. The controls are a system sheet (glass on
// iOS 26) that stays up and lets the strip behind it be touched: a tool bar
// (Paper, Film, Print, B&W, the five effects), the selected tool's control
// and the one primary, "Keep strip" (v5.2-7: Save and Archive merged; it
// keeps the strip in the Library). Presented after Film strip mode or from
// the Library.
struct StripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState

    @State private var viewModel: StripViewModel
    @State private var tool: StripTool = .paper
    @State private var isControlsPresented = true
    @State private var isClosing = false
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

    // A tool can disappear under the selection (Off hides Print and the
    // effects); Paper is always there to fall back on
    private var availableTools: [StripTool] {
        var tools: [StripTool] = [.paper, .film]
        if viewModel.isPrintPickerVisible { tools.append(.print) }
        tools.append(.blackAndWhite)
        if viewModel.areEffectsVisible { tools += FilmLook.Effect.allCases.map(StripTool.effect) }
        return tools
    }

    private var activeTool: StripTool {
        availableTools.contains(tool) ? tool : .paper
    }

    var body: some View {
        stripPreviews
            .safeAreaPadding(.top, UI.heroTopInset)
            .safeAreaPadding(.bottom, UI.sheetSmallDetent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { topBar }
            .background(theme.bg.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .appErrorAlert(errorState)
            .task {
                viewModel.errorState = errorState
                await viewModel.renderStrips()
            }
            .onChange(of: viewModel.customization) {
                Task { await viewModel.renderStrips() }
            }
            .sheet(isPresented: $isControlsPresented, onDismiss: finishClosing) {
                controlSheet
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
                    GlassIconButton(
                        systemImage: isDownloading ? "ellipsis" : "arrow.down.to.line",
                        label: "Download",
                        identifier: "strip.download",
                        isDisabled: isDownloading,
                        rotates: false,
                        action: download
                    )
                    .accessibilityHint("Saves the strip to your photo library")
                }
            }
            .disabled(viewModel.areActionsDisabled)
            .opacity(viewModel.areActionsDisabled ? Constants.CameraUI.disabledControlOpacity : 1)
        }
        .padding(.horizontal, Constants.DesignUI.gutter)
        .padding(.top, Constants.DesignUI.Space.s)
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

    // MARK: Controls sheet

    private var controlSheet: some View {
        VStack(spacing: UI.sheetSpacing) {
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
        .padding(.top, UI.sheetPadding)
        .foregroundStyle(theme.text)
        .tint(theme.accentFill)
        // Chrome text stops growing at the first accessibility size so the
        // sheet never pushes Keep strip off the screen
        .frmrChromeTypeSize()
        .frmrAnimation(.snap, value: viewModel.customization.filmStock)
        .presentationDetents([.height(UI.sheetSmallDetent), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(UI.sheetSmallDetent)))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .frmrSheetBackground()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var toolControl: some View {
        switch activeTool {
        case .paper: paperControl
        case .film: filmChips
        case .print: printChips
        case .blackAndWhite: blackAndWhiteControl
        case .effect(let effect): effectScrubber(for: effect)
        }
    }

    // v4 F8: white and black only, each labelled
    private var paperControl: some View {
        HStack(spacing: UI.swatchSpacing) {
            ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { option in
                SwatchButton(
                    color: option.color,
                    label: option.label,
                    identifier: "strip.background.\(option.settingsName)",
                    isSelected: option == viewModel.customization.background,
                    borderColor: theme.accentFill,
                    rimColor: theme.cardBorder,
                    action: { viewModel.customization.background = option }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // nil = As shot: every frame keeps the stock it was taken on
    private var filmChips: some View {
        ChipRow {
            ForEach(StripCustomization.stockChoices, id: \.self) { choice in
                chip(
                    label: StripCustomization.label(forStockChoice: choice),
                    accessibilityLabel: "Film: \(StripCustomization.label(forStockChoice: choice))",
                    identifier: "strip.stock.\(choice?.rawValue ?? "asShot")",
                    isSelected: choice == viewModel.customization.filmStock,
                    action: { viewModel.customization.filmStock = choice }
                )
            }
        }
    }

    private var printChips: some View {
        ChipRow {
            ForEach(viewModel.availablePrints) { printStock in
                chip(
                    label: printStock.label,
                    accessibilityLabel: "Print: \(printStock.label)",
                    identifier: "strip.print.\(printStock.rawValue)",
                    isSelected: printStock == viewModel.selectedPrint,
                    action: { viewModel.selectedPrint = printStock }
                )
            }
        }
    }

    private func chip(label: String, accessibilityLabel: String, identifier: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        ChoiceChip(
            label: label,
            accessibilityLabel: accessibilityLabel,
            identifier: identifier,
            isSelected: isSelected,
            selectedColor: theme.accentFill,
            selectedForeground: theme.onAccent,
            idleForeground: theme.text,
            idleBackground: theme.surface,
            action: action
        )
    }

    private var blackAndWhiteControl: some View {
        Toggle("Black & white", isOn: $viewModel.blackAndWhiteToggle)
            .font(.frmrLabel)
            .disabled(viewModel.isBlackAndWhiteLocked)
            .frame(minHeight: Constants.DesignUI.targetMin)
            .padding(.horizontal, UI.sheetPadding)
            .accessibilityHint("Renders the strip in black and white. Mono stocks are always black and white.")
            .accessibilityIdentifier("strip.blackAndWhite")
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

    // CONTRACT: StripViewModel.saveToCameraRoll() reports no success, so
    // there is no "Saved" confirmation yet
    private func download() {
        isDownloading = true
        Task {
            await viewModel.saveToCameraRoll()
            isDownloading = false
        }
    }

    // The sheet goes first; the cover follows once it has
    private func close() {
        isClosing = true
        isControlsPresented = false
    }

    private func finishClosing() {
        guard isClosing else {
            // The sheet can't be swiped away, but if the system drops it,
            // bring it back rather than strand the strip without controls
            isControlsPresented = true
            return
        }
        onDone()
        dismiss()
    }
}

/// Chips in a horizontal row inset by content margins, so the first and
/// last chip never clip at the sheet edge.
private struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.DesignUI.Space.s) { content }
        }
        .contentMargins(.horizontal, Constants.StripUI.sheetPadding, for: .scrollContent)
    }
}

// What the tool bar offers, in order. The selection is view state: the view
// model only cares about the customisation it produces.
private enum StripTool: Hashable {
    case paper
    case film
    case print
    case blackAndWhite
    case effect(FilmLook.Effect)

    init(id: String) {
        switch id {
        case "paper": self = .paper
        case "film": self = .film
        case "print": self = .print
        case "bw": self = .blackAndWhite
        default: self = FilmLook.Effect(rawValue: id).map(StripTool.effect) ?? .paper
        }
    }

    var id: String {
        switch self {
        case .paper: return "paper"
        case .film: return "film"
        case .print: return "print"
        case .blackAndWhite: return "bw"
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
        case .blackAndWhite:
            return ToolIconItem(id: id, title: "B&W", systemImage: "circle.lefthalf.filled", hint: "Render the strip in black and white")
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

private struct SwatchButton: View {
    let color: Color
    let label: String
    let identifier: String
    let isSelected: Bool
    let borderColor: Color
    let rimColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Constants.DesignUI.Space.xs) {
                Circle()
                    .fill(color)
                    // A hairline rim keeps the swatch that matches the page visible
                    .overlay(Circle().strokeBorder(rimColor, lineWidth: Constants.StripUI.swatchRimWidth))
                    .overlay(
                        Circle().strokeBorder(isSelected ? borderColor : .clear, lineWidth: Constants.StripUI.swatchBorderWidth)
                            .padding(-Constants.StripUI.swatchBorderWidth * 2)
                    )
                    .frame(width: Constants.StripUI.swatchDiameter, height: Constants.StripUI.swatchDiameter)
                Text(label)
                    .font(.frmrMeta)
            }
            .frame(minWidth: Constants.StripUI.swatchTapTarget, minHeight: Constants.StripUI.swatchTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paper, \(label.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
