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

    private var toggleCard: some View {
        VStack(spacing: 0) {
            Picker("Film stock", selection: $viewModel.customization.filmStock) {
                ForEach(StripCustomization.FilmStock.allCases) { stock in
                    Text(stock.label).tag(stock)
                }
            }
            .padding()
            Divider()
            Toggle("Black & white", isOn: $viewModel.customization.blackAndWhite)
                .padding()
        }
        .tint(theme.primary)
        .foregroundStyle(theme.text)
        .background(theme.card, in: RoundedRectangle(cornerRadius: Constants.EditorUI.cardCornerRadius))
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
    let onSelect: (StripCustomization.StripBackground) -> Void

    private let options: [StripCustomization.StripBackground] = [
        .cream, .white, .black, .custom(.appTealLight), .custom(.appAmber),
    ]

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                SwatchButton(
                    color: option.color,
                    isSelected: option == selected,
                    borderColor: borderColor,
                    action: { onSelect(option) }
                )
            }
        }
    }
}

private struct SwatchButton: View {
    let color: Color
    let isSelected: Bool
    let borderColor: Color
    let action: () -> Void

    private var ringColor: Color {
        isSelected ? borderColor : .clear
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: Constants.StripUI.swatchDiameter, height: Constants.StripUI.swatchDiameter)
                .overlay(
                    Circle().strokeBorder(ringColor, lineWidth: Constants.StripUI.swatchBorderWidth)
                )
        }
        .buttonStyle(.plain)
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
