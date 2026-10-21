import SwiftData
import SwiftUI

// v5 F6 Library Roll tab: a grid of the photos saved from Photo mode, each
// shown through its own current look. Tap opens the editor in re-edit mode;
// Select turns taps into a selection for Export to Photos or Make strip.
// The list is the view's @Query; every rule lives in RollViewModel.
struct RollView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ErrorState.self) private var errorState
    @Environment(OnboardingViewModel.self) private var onboarding
    @Query(sort: \RollPhoto.capturedAt, order: .reverse) private var photos: [RollPhoto]

    @State private var viewModel = RollViewModel()
    @State private var edit: PhotoEditViewModel?
    @State private var stripSource: RollStripSource?

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.RollUI.gridSpacing),
        count: Constants.RollUI.columns
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Constants.RollUI.gridSpacing) {
                ForEach(photos) { photo in
                    RollCell(
                        photo: photo,
                        isSelecting: viewModel.isSelecting,
                        isSelected: viewModel.isSelected(photo),
                        selectionNumber: viewModel.selectedIDs.firstIndex(of: photo.id).map { $0 + 1 },
                        tint: theme.primary,
                        action: { tapped(photo) }
                    )
                }
            }
        }
        .background(theme.background)
        .overlay {
            if photos.isEmpty {
                EmptyRollView(
                    textColor: theme.muted,
                    buttonColor: theme.primary,
                    onTakePhoto: { onboarding.selectedTab = .camera }
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isSelecting {
                SelectionBar(
                    count: viewModel.selectionCount,
                    exportedCount: viewModel.lastExportCount,
                    isExporting: viewModel.isExporting,
                    theme: theme,
                    onExport: exportSelected,
                    onMakeStrip: makeStrip
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel.isSelecting {
                    Button("Cancel", action: viewModel.endSelecting)
                        .accessibilityIdentifier("roll.cancelSelect")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.isSelecting {
                    Button("Select", action: beginSelecting)
                        .disabled(photos.isEmpty)
                        .accessibilityIdentifier("roll.select")
                }
            }
        }
        .task { viewModel.errorState = errorState }
        .fullScreenCover(item: $edit) { session in
            PhotoEditView(edit: session)
        }
        .fullScreenCover(item: $stripSource) { source in
            StripView(items: source.items, isPhotobooth: false, onDone: viewModel.endSelecting)
        }
    }

    private func beginSelecting() {
        viewModel.isSelecting = true
    }

    private func tapped(_ photo: RollPhoto) {
        if viewModel.isSelecting {
            viewModel.toggleSelection(of: photo, limit: Constants.Roll.maxPhotosPerStrip)
        } else {
            open(photo)
        }
    }

    private func open(_ photo: RollPhoto) {
        guard let session = PhotoEditViewModel(editing: photo) else {
            errorState.raise(.persistenceFailed(reason: "This photo's file couldn't be read."))
            return
        }
        session.onFinish = { _ in edit = nil }
        edit = session
    }

    private func exportSelected() {
        let selection = viewModel.selectedPhotos(in: photos)
        Task { await viewModel.export(selection) }
    }

    private func makeStrip() {
        let items = RollViewModel.stripItems(from: viewModel.selectedPhotos(in: photos))
        stripSource = RollStripSource(items: items)
    }
}

// fullScreenCover(item:) wants an identity; each tap on Make strip is a new strip
private struct RollStripSource: Identifiable {
    let id = UUID()
    let items: [StripItem]
}

private struct RollCell: View {
    let photo: RollPhoto
    let isSelecting: Bool
    let isSelected: Bool
    let selectionNumber: Int?
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RollLookImage(photo: photo, contentMode: .fill) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipped()
                .overlay {
                    Rectangle()
                        .fill(.black.opacity(isSelected ? Constants.RollUI.selectedDimOpacity : 0))
                }
                .overlay {
                    Rectangle()
                        .strokeBorder(isSelected ? tint : .clear, lineWidth: Constants.RollUI.selectionRingWidth)
                }
                .overlay(alignment: .topTrailing) {
                    SelectionBadge(isVisible: isSelecting, number: selectionNumber, tint: tint)
                        .padding(Constants.RollUI.selectionBadgePadding)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo from \(photo.capturedAt.entryDetailTimestamp)")
        .accessibilityHint(isSelecting ? "Selects this photo" : "Opens the editor")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("roll.photo")
    }
}

private struct SelectionBadge: View {
    let isVisible: Bool
    let number: Int?
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(number == nil ? Color.black.opacity(Constants.ReviewUI.overlayOpacity) : tint)
            Circle()
                .strokeBorder(.white, lineWidth: Constants.CameraUI.lastPhotoBorderWidth)
            if let number {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Constants.RollUI.selectionBadgeSize, height: Constants.RollUI.selectionBadgeSize)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(true)
    }
}

private struct SelectionBar: View {
    let count: Int
    let exportedCount: Int
    let isExporting: Bool
    let theme: ThemePalette
    let onExport: () -> Void
    let onMakeStrip: () -> Void

    private var summary: String {
        if exportedCount > 0 { return "Saved \(exportedCount) to Photos" }
        return count == 0 ? "Pick up to \(Constants.Roll.maxPhotosPerStrip)" : "\(count) selected"
    }

    var body: some View {
        HStack(spacing: Constants.RollUI.toolbarSpacing) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("roll.selectionSummary")
            Button(action: onExport) {
                if isExporting {
                    ProgressView()
                } else {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(count == 0 || isExporting)
            .accessibilityHint("Saves the selected photos to your photo library with their film looks")
            .accessibilityIdentifier("roll.export")
            Button(action: onMakeStrip) {
                Label("Make strip", systemImage: "film")
            }
            .disabled(count == 0 || isExporting)
            .accessibilityHint("Builds a film strip from the selected photos")
            .accessibilityIdentifier("roll.makeStrip")
        }
        .font(.subheadline.weight(.semibold))
        .tint(theme.primary)
        .padding()
        .background(theme.card)
    }
}

private struct EmptyRollView: View {
    let textColor: Color
    let buttonColor: Color
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: Constants.RollUI.emptySpacing) {
            Image(systemName: "camera.aperture")
                .font(.system(size: Constants.RollUI.emptyIconSize, weight: .light))
                .foregroundStyle(textColor)
            Text("Your roll is empty")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(textColor)
            Text("Photos you save from the camera land here, ready to edit again.")
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
            Button(action: onTakePhoto) {
                Text("Take a photo")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Constants.RollUI.emptyButtonHorizontalPadding)
                    .frame(minHeight: Constants.RollUI.emptyButtonHeight)
                    .background(buttonColor, in: RoundedRectangle(cornerRadius: Constants.RollUI.emptyButtonCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the camera")
            .accessibilityIdentifier("roll.takePhoto")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roll.empty")
    }
}
