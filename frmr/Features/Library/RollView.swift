import SwiftData
import SwiftUI

// v5 F6 Library Roll tab: a grid of the photos saved from Photo mode, each
// shown through its own current look. Tap opens the editor in re-edit mode;
// Select turns taps into a selection for Export to Photos or Make strip.
// The list is the view's @Query; every rule lives in RollViewModel.
struct RollView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorState.self) private var errorState
    @Environment(OnboardingViewModel.self) private var onboarding
    @Query(sort: \RollPhoto.capturedAt, order: .reverse) private var photos: [RollPhoto]
    // v5.1-6: the badge set comes from the entries the view already queries
    @Query private var entries: [DiaryEntry]

    @State private var viewModel = RollViewModel()
    @State private var edit: PhotoEditViewModel?
    @State private var stripSource: RollStripSource?
    // v5.1-7: deleting selected photos asks what to do with linked entries
    @State private var isDeletePromptPresented = false
    @State private var linkedEntryCount = 0

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }
    private var accent: Color { theme.tint }
    private var photosWithEntry: Set<UUID> { RollViewModel.linkedPhotoIDs(in: entries) }

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
                        hasDiaryEntry: photosWithEntry.contains(photo.id),
                        selectionNumber: viewModel.selectedIDs.firstIndex(of: photo.id).map { $0 + 1 },
                        tint: accent,
                        action: { tapped(photo) }
                    )
                }
            }
            .padding(.horizontal, Constants.RollUI.gridInset)
        }
        .frmrTabBarScrollInsets()
        .background(theme.background)
        .overlay {
            if photos.isEmpty {
                EmptyRollView(
                    textColor: theme.muted,
                    buttonColor: theme.accentFill,
                    buttonTextColor: theme.onAccent,
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
                    accent: accent,
                    destructive: theme.destructive,
                    mutedColor: theme.muted,
                    onExport: exportSelected,
                    onMakeStrip: makeStrip,
                    onDelete: askToDelete
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
        .confirmationDialog(
            deletePromptTitle,
            isPresented: $isDeletePromptPresented,
            titleVisibility: .visible
        ) {
            deletePromptButtons
        }
        .fullScreenCover(item: $edit) { session in
            PhotoEditView(edit: session)
        }
        .fullScreenCover(item: $stripSource) { source in
            StripView(items: source.items, isPhotobooth: false, onDone: viewModel.endSelecting)
        }
    }

    // MARK: Delete prompt (v5.1-7)

    private var deletePromptTitle: String {
        let count = viewModel.selectionCount
        let photoText = count == 1 ? "this photo" : "these \(count) photos"
        guard linkedEntryCount > 0 else { return "Delete \(photoText)? This can't be undone." }
        let entryText = linkedEntryCount == 1 ? "1 diary entry is" : "\(linkedEntryCount) diary entries are"
        return "\(entryText) about \(photoText). Delete the entries too, or keep them with their own copy of the photo?"
    }

    @ViewBuilder
    private var deletePromptButtons: some View {
        if linkedEntryCount > 0 {
            Button("Keep entries") { deleteSelected(entries: .keepEntry) }
                .accessibilityIdentifier("roll.delete.keepEntries")
            Button("Delete photos and diary entries", role: .destructive) { deleteSelected(entries: .deleteBoth) }
                .accessibilityIdentifier("roll.delete.deleteBoth")
        } else {
            Button("Delete", role: .destructive) { deleteSelected(entries: .keepEntry) }
                .accessibilityIdentifier("roll.delete.confirm")
        }
    }

    private func askToDelete() {
        let selection = viewModel.selectedPhotos(in: photos)
        linkedEntryCount = selection.reduce(0) { $0 + RollViewModel.linkedEntryCount(for: $1, in: modelContext) }
        isDeletePromptPresented = true
    }

    private func deleteSelected(entries choice: RollViewModel.RollDeletion) {
        do {
            for photo in viewModel.selectedPhotos(in: photos) {
                try RollViewModel.delete(photo, entries: choice, context: modelContext)
            }
        } catch let error as AppError {
            errorState.raise(error)
        } catch {
            errorState.raise(.persistenceFailed(reason: error.localizedDescription))
        }
        viewModel.endSelecting()
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
    let hasDiaryEntry: Bool
    let selectionNumber: Int?
    let tint: Color
    let action: () -> Void

    private var cellShape: RoundedRectangle { RoundedRectangle(cornerRadius: Constants.RollUI.cellCornerRadius) }
    private var accessibilityText: String {
        let base = "Photo from \(photo.capturedAt.entryDetailTimestamp)"
        return hasDiaryEntry ? base + ", has a diary entry" : base
    }

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
                .clipShape(cellShape)
                .overlay {
                    cellShape
                        .fill(.black.opacity(isSelected ? Constants.RollUI.selectedDimOpacity : 0))
                }
                .overlay {
                    cellShape
                        .strokeBorder(isSelected ? tint : .clear, lineWidth: Constants.RollUI.selectionRingWidth)
                }
                .overlay(alignment: .topTrailing) {
                    SelectionBadge(isVisible: isSelecting, number: selectionNumber, tint: tint)
                        .padding(Constants.RollUI.selectionBadgePadding)
                }
                .overlay(alignment: .bottomLeading) {
                    DiaryBadge(isVisible: hasDiaryEntry)
                        .padding(Constants.RollUI.diaryBadgePadding)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isSelecting ? "Selects this photo" : "Opens the editor")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("roll.photo")
    }
}

// v5.1-6: a small book on photos that have a diary entry. Decorative: the
// cell's own label says "has a diary entry".
private struct DiaryBadge: View {
    let isVisible: Bool

    var body: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: Constants.RollUI.diaryBadgeIconSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Constants.RollUI.diaryBadgeSize, height: Constants.RollUI.diaryBadgeSize)
            .frmrAdaptiveGlass(in: Circle())
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
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

// v5.1 F10: the selection bar is a floating glass toolbar of icon buttons
private struct SelectionBar: View {
    let count: Int
    let exportedCount: Int
    let isExporting: Bool
    let accent: Color
    let destructive: Color
    let mutedColor: Color
    let onExport: () -> Void
    let onMakeStrip: () -> Void
    let onDelete: () -> Void

    private var summary: String {
        if exportedCount > 0 { return "Saved \(exportedCount) to Photos" }
        return count == 0 ? "Pick up to \(Constants.Roll.maxPhotosPerStrip)" : "\(count) selected"
    }

    var body: some View {
        HStack(spacing: Constants.RollUI.toolbarSpacing) {
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(mutedColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Constants.RollUI.toolbarHorizontalPadding)
                .accessibilityIdentifier("roll.selectionSummary")
            ToolbarIcon(
                systemImage: "square.and.arrow.down",
                label: "Export",
                hint: "Saves the selected photos to your photo library with their film looks",
                identifier: "roll.export",
                isBusy: isExporting,
                isEnabled: count > 0 && !isExporting,
                tint: accent,
                action: onExport
            )
            ToolbarIcon(
                systemImage: "film",
                label: "Make strip",
                hint: "Builds a film strip from the selected photos",
                identifier: "roll.makeStrip",
                isBusy: false,
                isEnabled: count > 0 && !isExporting,
                tint: accent,
                action: onMakeStrip
            )
            ToolbarIcon(
                systemImage: "trash",
                label: "Delete",
                hint: "Deletes the selected photos from your roll",
                identifier: "roll.delete",
                isBusy: false,
                isEnabled: count > 0 && !isExporting,
                tint: destructive,
                action: onDelete
            )
        }
        .padding(.horizontal, Constants.RollUI.toolbarHorizontalPadding)
        .padding(.vertical, Constants.RollUI.toolbarVerticalPadding)
        .frmrAdaptiveGlassCapsule()
        .padding(.horizontal, Constants.RollUI.toolbarOuterPadding)
        .padding(.bottom, Constants.RollUI.toolbarOuterPadding)
    }
}

private struct ToolbarIcon: View {
    let systemImage: String
    let label: String
    let hint: String
    let identifier: String
    let isBusy: Bool
    let isEnabled: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: Constants.RollUI.toolbarIconSize, weight: .medium))
                }
            }
            .frame(width: Constants.RollUI.toolbarButtonSize, height: Constants.RollUI.toolbarButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Constants.CameraUI.disabledControlOpacity)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

private struct EmptyRollView: View {
    let textColor: Color
    let buttonColor: Color
    let buttonTextColor: Color
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(spacing: Constants.RollUI.emptySpacing) {
            Image(systemName: "camera.aperture")
                .font(.system(size: Constants.RollUI.emptyIconSize, weight: .light))
                .foregroundStyle(textColor)
                .accessibilityHidden(true)
            Text("Your roll is empty")
                .font(.title3.weight(.medium))
                .foregroundStyle(textColor)
            Text("Photos you save from the camera land here, ready to edit again.")
                .font(.subheadline)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
            Button(action: onTakePhoto) {
                Text("Take a photo")
                    .font(.headline)
                    .foregroundStyle(buttonTextColor)
                    .padding(.horizontal, Constants.RollUI.emptyButtonHorizontalPadding)
                    .frame(minHeight: Constants.RollUI.emptyButtonHeight)
                    .background(buttonColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, Constants.RollUI.emptySpacing)
            .accessibilityHint("Opens the camera")
            .accessibilityIdentifier("roll.takePhoto")
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roll.empty")
    }
}
