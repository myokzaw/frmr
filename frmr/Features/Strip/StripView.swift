import SwiftData
import SwiftUI

// Strip preview + customisation (project.md §2, screen 4; v5.1 F10). The
// strip is the hero; controls sit in a glass sheet at the bottom using the
// editor's pattern: a tool icon bar (Paper, Film, Print, B&W, then the five
// effects) and one control for the selected tool — swatches, chips, a toggle
// or the tick-mark scrubber. Archive and Share are icons; Save is the one
// primary action. Presented after photobooth capture or from the Library.
struct StripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ErrorState.self) private var errorState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: StripViewModel
    @State private var tool: StripTool = .paper
    private let onDone: () -> Void

    private typealias UI = Constants.StripUI

    init(items: [StripItem], isPhotobooth: Bool, onDone: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: StripViewModel(items: items, isPhotobooth: isPhotobooth))
        self.onDone = onDone
    }

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

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
        // The close row is its own band, so the button never covers the strip
        VStack(spacing: 0) {
            HStack {
                GlassIconButton(
                    systemImage: "xmark",
                    label: "Close",
                    identifier: "strip.close",
                    foreground: theme.text,
                    rotates: false,
                    action: close
                )
                Spacer()
            }
            .padding(UI.closeButtonPadding)
            stripPreviews
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { controlSheet }
            .appErrorAlert(errorState)
            .task {
                viewModel.errorState = errorState
                await viewModel.renderStrips()
            }
            .onChange(of: viewModel.customization) {
                Task { await viewModel.renderStrips() }
            }
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
                            .frame(maxHeight: geometry.size.height * UI.previewHeightFraction)
                            .shadow(
                                color: .black.opacity(UI.previewShadowOpacity),
                                radius: UI.previewShadowRadius / 2
                            )
                            .accessibilityLabel("Strip preview")
                    }
                }
                .padding(.horizontal, UI.previewHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    // MARK: Glass sheet

    private var controlSheet: some View {
        VStack(spacing: UI.sheetSpacing) {
            toolControl
                .frame(minHeight: UI.toolPanelHeight, alignment: .top)
            ToolIconBar(
                items: availableTools.map(\.item),
                selectedID: activeTool.id,
                modifiedIDs: modifiedToolIDs,
                identifierPrefix: "strip.tool",
                selectedColor: .appAmber,
                idleColor: theme.text,
                onSelect: { tool = StripTool(id: $0) }
            )
            actionRow
        }
        .padding(UI.sheetPadding)
        .foregroundStyle(theme.text)
        .tint(.appAmber)
        // Chrome text stops growing at the first accessibility size so the
        // sheet never pushes Save off the screen
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frmrGlass(in: UnevenRoundedRectangle(topLeadingRadius: UI.sheetCornerRadius, topTrailingRadius: UI.sheetCornerRadius))
        .animation(reduceMotion ? nil : .easeInOut(duration: UI.controlRowAnimationDuration), value: viewModel.customization.filmStock)
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

    // v4 F8: white and black only
    private var paperControl: some View {
        HStack(spacing: UI.swatchSpacing) {
            ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { option in
                SwatchButton(
                    color: option.color,
                    label: option.label,
                    identifier: "strip.background.\(option.settingsName)",
                    isSelected: option == viewModel.customization.background,
                    borderColor: .appAmber,
                    rimColor: theme.cardBorder,
                    action: { viewModel.customization.background = option }
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: Constants.ReviewUI.stockChipHeight)
    }

    // nil = As shot: every frame keeps the stock it was taken on
    private var filmChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.PhotoEditUI.chipSpacing) {
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
    }

    private var printChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.PhotoEditUI.chipSpacing) {
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
    }

    private func chip(label: String, accessibilityLabel: String, identifier: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        ChoiceChip(
            label: label,
            accessibilityLabel: accessibilityLabel,
            identifier: identifier,
            isSelected: isSelected,
            selectedColor: .appAmber,
            selectedForeground: .appBlack,
            idleForeground: theme.text,
            idleBackground: theme.text.opacity(UI.iconFillOpacity),
            action: action
        )
    }

    private var blackAndWhiteControl: some View {
        Toggle("Black & white", isOn: $viewModel.blackAndWhiteToggle)
            .disabled(viewModel.isBlackAndWhiteLocked)
            .frame(minHeight: Constants.ReviewUI.stockChipHeight)
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
            tint: .appAmber
        )
    }

    // A dot under each effect whose value is off the stock default
    private var modifiedToolIDs: Set<String> {
        Set(FilmLook.Effect.allCases
            .filter { viewModel.customization.strengths[$0] != $0.defaultStrength }
            .map(\.rawValue))
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: UI.actionSpacing) {
            Button(action: archiveStrip) {
                PanelIconLabel(systemImage: "archivebox", fill: theme.text.opacity(UI.iconFillOpacity))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive")
            .accessibilityHint("Keeps the strip in your library without saving it to Photos")
            .accessibilityIdentifier("strip.archive")

            ShareLink(items: shareImages) { _ in
                SharePreview("Film strip")
            } label: {
                PanelIconLabel(systemImage: "square.and.arrow.up", fill: theme.text.opacity(UI.iconFillOpacity))
            }
            .accessibilityLabel("Share")
            .accessibilityIdentifier("strip.share")

            Button(action: saveStrip) {
                Text("Save")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.appBlack)
                    .frame(maxWidth: .infinity, minHeight: UI.saveButtonHeight)
                    .background(Color.appAmber, in: RoundedRectangle(cornerRadius: UI.saveButtonCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Saves the strip to Photos and your library")
            .accessibilityIdentifier("strip.save")
        }
        .disabled(viewModel.areActionsDisabled)
        .opacity(viewModel.areActionsDisabled ? Constants.CameraUI.disabledControlOpacity : 1)
    }

    // OPEN: archive behavior TBD (project.md §13 #6) — currently saves to
    // the in-app library only, without touching the camera roll
    private func archiveStrip() {
        if viewModel.persist(context: modelContext) {
            close()
        }
    }

    // Save = camera roll + in-app library, both from one explicit tap
    private func saveStrip() {
        Task {
            await viewModel.saveToCameraRoll()
            if viewModel.persist(context: modelContext) {
                close()
            }
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

    var item: ToolIconItem {
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
            return ToolIconItem(id: id, title: effect.label, systemImage: effect.toolSymbolName, hint: effect.toolHint)
        }
    }
}

private struct PanelIconLabel: View {
    let systemImage: String
    let fill: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Constants.ScrubberUI.glassButtonIconSize, weight: .semibold))
            .frame(width: Constants.ScrubberUI.glassButtonSize, height: Constants.StripUI.saveButtonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: Constants.StripUI.saveButtonCornerRadius))
            .contentShape(Rectangle())
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

    private var ringColor: Color {
        isSelected ? borderColor : .clear
    }

    // The selection ring is visual only; VoiceOver hears it as a trait
    private var selectionTraits: AccessibilityTraits {
        isSelected ? .isSelected : []
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                // A hairline rim keeps the swatch that matches the page
                // (black in dark mode) visible
                .overlay(
                    Circle().strokeBorder(rimColor, lineWidth: Constants.StripUI.swatchRimWidth)
                )
                .overlay(
                    Circle().strokeBorder(ringColor, lineWidth: Constants.StripUI.swatchBorderWidth)
                        .padding(-Constants.StripUI.swatchBorderWidth * 2)
                )
                .frame(width: Constants.StripUI.swatchDiameter, height: Constants.StripUI.swatchDiameter)
                .frame(minWidth: Constants.StripUI.swatchTapTarget, minHeight: Constants.StripUI.swatchTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) background")
        .accessibilityAddTraits(selectionTraits)
        .accessibilityIdentifier(identifier)
    }
}
