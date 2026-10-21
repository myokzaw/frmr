import SwiftData
import SwiftUI

// Strip preview + customization (project.md §2, screen 4). Presented after
// photobooth capture or from the Library's "compile today" action.
struct StripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ErrorState.self) private var errorState

    @State private var viewModel: StripViewModel
    private let onDone: () -> Void

    init(items: [StripItem], isPhotobooth: Bool, onDone: @escaping () -> Void = {}) {
        _viewModel = State(initialValue: StripViewModel(items: items, isPhotobooth: isPhotobooth))
        self.onDone = onDone
    }

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

    private var shareImages: [Image] {
        viewModel.stripImages.map { Image(uiImage: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.EditorUI.buttonPadding) {
                    stripPreviews
                    BackgroundSwatchRow(
                        selected: viewModel.customization.background,
                        borderColor: theme.primary,
                        rimColor: theme.cardBorder,
                        onSelect: selectBackground
                    )
                    toggleCard
                    actionRow
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle("Strip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                }
            }
        }
        .appErrorAlert(errorState)
        .task {
            viewModel.errorState = errorState
            await viewModel.renderStrips()
        }
        .onChange(of: viewModel.customization) {
            Task { await viewModel.renderStrips() }
        }
    }

    private var stripPreviews: some View {
        VStack(spacing: Constants.EditorUI.buttonPadding) {
            ForEach(Array(viewModel.stripImages.enumerated()), id: \.offset) { _, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.Strip.width * Constants.Strip.renderScale)
                    .shadow(
                        color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                        radius: Constants.StripUI.previewShadowRadius / 2
                    )
            }
        }
        .padding(.vertical)
    }

    // v4 F7 controls card. Which rows show is decided by the ViewModel; the
    // previous strip stays on screen while a change re-renders.
    private var toggleCard: some View {
        VStack(spacing: 0) {
            // Outside a Form a menu Picker shows only its value, so the row
            // supplies its own label (the Picker keeps it for VoiceOver)
            StripPickerRow(title: "Film stock") {
                Picker("Film stock", selection: $viewModel.customization.filmStock) {
                    // nil = As shot: every frame keeps the stock it was taken on
                    ForEach(StripCustomization.stockChoices, id: \.self) { choice in
                        Text(StripCustomization.label(forStockChoice: choice)).tag(choice)
                    }
                }
                .accessibilityHint("Chooses the film the strip is rendered on. As shot keeps each photo's own film.")
                .accessibilityIdentifier("strip.filmStock")
            }

            if viewModel.isPrintPickerVisible {
                Divider()
                StripPickerRow(title: "Print") {
                    Picker("Print", selection: $viewModel.selectedPrint) {
                        ForEach(viewModel.availablePrints) { printStock in
                            Text(printStock.label).tag(printStock)
                        }
                    }
                    .accessibilityHint("Chooses the paper the film is printed on")
                    .accessibilityIdentifier("strip.print")
                }
                .transition(.opacity)
            }

            if viewModel.areEffectsVisible {
                effectRows
                    .transition(.opacity)
            }

            Divider()
            Toggle("Black & white", isOn: $viewModel.blackAndWhiteToggle)
                .disabled(viewModel.isBlackAndWhiteLocked)
                .padding()
                .accessibilityHint("Renders the strip in black and white. Mono stocks are always black and white.")
                .accessibilityIdentifier("strip.blackAndWhite")
        }
        .tint(theme.primary)
        .foregroundStyle(theme.text)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Constants.EditorUI.cardCornerRadius))
        .animation(
            .easeInOut(duration: Constants.StripUI.controlRowAnimationDuration),
            value: viewModel.customization.filmStock
        )
    }

    // v5 F5: strength sliders replace the v4 on/off toggles. 100% is the
    // v4 strength of an effect that was on; the sliders reach 150%.
    private var effectRows: some View {
        VStack(spacing: 0) {
            Divider()
            StripGroupLabel(title: "Effects", color: theme.muted)
            EffectSliders(
                strength: { viewModel.customization.strengths[$0] },
                setStrength: { viewModel.customization.strengths[$1] = $0 },
                identifierPrefix: "strip.slider",
                textColor: theme.text,
                tint: theme.primary
            )
            .padding(.horizontal)
        }
    }

    private var actionRow: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            StripActionButton(label: "Save", theme: theme, action: saveStrip)
            ShareLink(items: shareImages) { _ in
                SharePreview("Film strip")
            } label: {
                StripActionLabel(label: "Share", theme: theme)
            }
            // OPEN: archive behavior TBD (project.md §13 #6) — currently saves to
            // the in-app library only, without touching the camera roll
            StripActionButton(label: "Archive", theme: theme, action: archiveStrip)
        }
        .disabled(viewModel.areActionsDisabled)
    }

    private func selectBackground(_ background: StripCustomization.StripBackground) {
        viewModel.customization.background = background
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

    private func archiveStrip() {
        if viewModel.persist(context: modelContext) {
            close()
        }
    }

    private func close() {
        onDone()
        dismiss()
    }
}

private struct BackgroundSwatchRow: View {
    let selected: StripCustomization.StripBackground
    let borderColor: Color
    let rimColor: Color
    let onSelect: (StripCustomization.StripBackground) -> Void

    // v4 F8: white and black only
    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { option in
                SwatchButton(
                    color: option.color,
                    label: option.label,
                    identifier: "strip.background.\(option.settingsName)",
                    isSelected: option == selected,
                    borderColor: borderColor,
                    rimColor: rimColor,
                    action: { onSelect(option) }
                )
            }
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

// A titled row holding a menu Picker, laid out like the card's Toggle rows
private struct StripPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let picker: Content

    var body: some View {
        HStack {
            Text(title)
                .accessibilityHidden(true)
            Spacer()
            picker
                .labelsHidden()
        }
        .padding()
    }
}

// Uppercase muted label that opens a group of rows inside the controls card
private struct StripGroupLabel: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(Constants.StripUI.groupLabelTracking)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StripActionButton: View {
    let label: String
    let theme: ThemePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StripActionLabel(label: label, theme: theme)
        }
        .buttonStyle(.plain)
    }
}

private struct StripActionLabel: View {
    let label: String
    let theme: ThemePalette

    var body: some View {
        Text(label)
            .font(.system(size: Constants.StripUI.actionFontSize, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Constants.CameraUI.chipHorizontalPadding)
            .background(theme.card, in: RoundedRectangle(cornerRadius: Constants.StripUI.actionCornerRadius))
    }
}
