import SwiftData
import SwiftUI

// v5 F6 / v5.2 S5 Library Roll: a contact sheet. Each day is a section with
// a sticky header and its frame count; photos sit in a 3-column grid of 4:5
// cells with 2-pt gutters, each through its own current look, and a line of
// edge print (frame numbers and stock codes) runs under each day. Paper in
// light mode, dark in dark (v5.2-6). Tap opens the editor in re-edit mode;
// Select turns taps into a numbered selection with a system bottom bar for
// Export, Make strip and Delete. Every rule lives in RollViewModel.
struct RollView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.modelContext) private var modelContext
    @Environment(\.selectAppTab) private var selectAppTab
    @Environment(ErrorState.self) private var errorState
    @Query(sort: \RollPhoto.capturedAt, order: .reverse) private var photos: [RollPhoto]
    // v5.1-6: the badge set comes from the entries the view already queries
    @Query private var entries: [DiaryEntry]

    @State private var viewModel = RollViewModel()
    @State private var edit: PhotoEditViewModel?
    @State private var stripSource: RollStripSource?
    // v5.1-7: deleting selected photos asks what to do with linked entries;
    // nil = the count couldn't be read, so the question offers both answers
    @State private var isDeletePromptPresented = false
    @State private var linkedEntryCount: Int?

    private typealias UI = Constants.RollUI
    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }
    private var photosWithEntry: Set<UUID> { RollViewModel.linkedPhotoIDs(in: entries) }
    private var sections: [RollDaySection] { RollViewModel.daySections(photos) }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.DesignUI.contactSheetGutter),
        count: Constants.RollUI.columns
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Constants.DesignUI.contactSheetGutter, pinnedViews: .sectionHeaders) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.photos) { photo in
                            RollCell(
                                photo: photo,
                                isSelecting: viewModel.isSelecting,
                                isSelected: viewModel.isSelected(photo),
                                hasDiaryEntry: photosWithEntry.contains(photo.id),
                                selectionNumber: viewModel.selectedIDs.firstIndex(of: photo.id).map { $0 + 1 },
                                selection: theme.selectedIndicator,
                                action: { tapped(photo) }
                            )
                        }
                    } header: {
                        DayHeader(title: section.title, count: section.photos.count, theme: theme)
                    } footer: {
                        EdgePrint(text: RollEdgePrint.text(for: section.photos), color: theme.textMuted)
                    }
                }
            }
            .padding(.horizontal, Constants.DesignUI.gutter)
        }
        .frmrTabBarScrollInsets()
        .overlay {
            if photos.isEmpty {
                EmptyRollView(theme: theme, onTakePhoto: { selectAppTab(.camera) })
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
                if !viewModel.isSelecting && !photos.isEmpty {
                    Button("Select", action: beginSelecting)
                        .accessibilityIdentifier("roll.select")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if viewModel.isSelecting {
                    selectionBar
                }
            }
        }
        // While selecting, the bottom bar takes the tab bar's place
        .toolbar(viewModel.isSelecting ? .hidden : .visible, for: .tabBar)
        .task { viewModel.errorState = errorState }
        .sensoryFeedback(.warning, trigger: isDeletePromptPresented) { _, shown in shown }
        .confirmationDialog(
            RollPromptText.deleteTitle(photoCount: viewModel.selectionCount, linkedEntries: linkedEntryCount),
            isPresented: $isDeletePromptPresented,
            titleVisibility: .visible
        ) {
            deletePromptButtons
        }
        .fullScreenCover(item: $edit) { session in
            ReEditFlowView(session: session) { edit = nil }
        }
        .fullScreenCover(item: $stripSource) { source in
            StripView(items: source.items, isPhotobooth: false, onDone: viewModel.endSelecting)
        }
    }

    // MARK: Selection bar (system bottom bar)

    @ViewBuilder private var selectionBar: some View {
        let isEnabled = viewModel.hasSelection && !viewModel.isExporting
        Button(action: exportSelected) {
            if viewModel.isExporting {
                ProgressView()
            } else {
                Label("Export", systemImage: "square.and.arrow.down")
            }
        }
        .disabled(!isEnabled)
        .accessibilityHint("Saves the selected photos to your photo library with their film looks")
        .accessibilityIdentifier("roll.export")
        Spacer()
        Text(RollSelectionText.summary(count: viewModel.selectionCount, exportedCount: viewModel.lastExportCount))
            .font(.frmrMeta)
            .foregroundStyle(theme.textMuted)
            .fixedSize()
            .accessibilityLabel("\(viewModel.selectionCount) selected")
            .accessibilityIdentifier("roll.selectionSummary")
        Spacer()
        Button(action: makeStrip) {
            Label("Make strip", systemImage: "film.stack")
        }
        .disabled(!isEnabled)
        .accessibilityHint("Builds a film strip from the selected photos")
        .accessibilityIdentifier("roll.makeStrip")
        Button(role: .destructive, action: askToDelete) {
            Label("Delete", systemImage: "trash")
        }
        .tint(theme.destructive)
        .disabled(!isEnabled)
        .accessibilityHint("Deletes the selected photos from your roll")
        .accessibilityIdentifier("roll.delete")
    }

    // MARK: Delete prompt (v5.1-7)

    @ViewBuilder
    private var deletePromptButtons: some View {
        if RollPromptText.asksAboutEntries(linkedEntryCount) {
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
        let counts = viewModel.selectedPhotos(in: photos).map { RollViewModel.linkedEntryCountIfKnown(for: $0, in: modelContext) }
        linkedEntryCount = RollSelectionText.total(counts)
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

/// Text helpers for the Roll's selection bar and prompts. Pure.
nonisolated enum RollSelectionText {
    static func summary(count: Int, exportedCount: Int, limit: Int = Constants.Roll.maxPhotosPerStrip) -> String {
        if exportedCount > 0 { return "Saved \(exportedCount) to Photos" }
        return count == 0 ? "Pick up to \(limit)" : "\(count) of \(limit)"
    }

    /// The sum of per-photo counts; nil if any one couldn't be read.
    static func total(_ counts: [Int?]) -> Int? {
        counts.reduce(Optional(0)) { sum, count in
            guard let sum, let count else { return nil }
            return sum + count
        }
    }
}

/// The contact sheet's edge print: frame numbers then the day's stock codes,
/// "1 ▸ 2 ▸ 3   P400 C500". Pure.
enum RollEdgePrint {
    static func text(for photos: [RollPhoto]) -> String {
        let frames = (1...max(photos.count, 1)).map(String.init).joined(separator: " \u{25B8} ")
        var codes: [String] = []
        for photo in photos.reversed() {
            let code = photo.look.stock.shortCode
            if !codes.contains(code) { codes.append(code) }
        }
        return ([frames] + codes).joined(separator: "   ")
    }
}

// fullScreenCover(item:) wants an identity; each tap on Make strip is a new strip
private struct RollStripSource: Identifiable {
    let id = UUID()
    let items: [StripItem]
}

private struct DayHeader: View {
    let title: String
    let count: Int
    let theme: ThemePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.frmrLabel.weight(.semibold))
                .foregroundStyle(theme.text)
            Spacer()
            Text(count == 1 ? "1 frame" : "\(count) frames")
                .font(.frmrMeta)
                .foregroundStyle(theme.textMuted)
        }
        .padding(.vertical, Constants.DesignUI.Space.s)
        .background(theme.bg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("roll.dayHeader")
    }
}

private struct EdgePrint: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .frmrCodeStyle()
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Constants.DesignUI.Space.xs)
            .padding(.bottom, Constants.DesignUI.Space.l)
            .accessibilityHidden(true)
    }
}

private struct RollCell: View {
    let photo: RollPhoto
    let isSelecting: Bool
    let isSelected: Bool
    let hasDiaryEntry: Bool
    let selectionNumber: Int?
    let selection: Color
    let action: () -> Void

    private typealias UI = Constants.RollUI

    private var accessibilityText: String {
        let time = photo.capturedAt.formatted(date: .omitted, time: .shortened)
        let base = "Photo, \(time), \(photo.look.stock.label)"
        return hasDiaryEntry ? base + ", has a diary entry" : base
    }

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
                .overlay {
                    RollLookImage(photo: photo, contentMode: .fill) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipped()
                .overlay {
                    Rectangle()
                        .strokeBorder(isSelected ? selection : .clear, lineWidth: UI.selectionRingWidth)
                }
                .overlay(alignment: .topTrailing) {
                    SelectionBadge(isVisible: isSelecting, number: selectionNumber, tint: selection)
                        .padding(UI.selectionBadgePadding)
                }
                .overlay(alignment: .bottomTrailing) {
                    DiaryBadge(isVisible: hasDiaryEntry)
                        .padding(UI.diaryBadgePadding)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isSelecting ? "Selects this photo" : "Opens the editor")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("roll.photo")
    }
}

// v5.1-6: a small book on photos that have a diary entry, on a dark disc
// over the photo. Decorative: the cell's own label says "has a diary entry".
private struct DiaryBadge: View {
    let isVisible: Bool

    var body: some View {
        Image(systemName: "book.closed.fill")
            .font(.system(size: Constants.RollUI.diaryBadgeIconSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: Constants.RollUI.diaryBadgeSize, height: Constants.RollUI.diaryBadgeSize)
            .frmrGlass(in: Circle())
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

struct SelectionBadge: View {
    let isVisible: Bool
    let number: Int?
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(number == nil ? Color.black.opacity(Constants.RollUI.badgeScrimOpacity) : tint)
            Circle()
                .strokeBorder(.white, lineWidth: Constants.CameraUI.lastPhotoBorderWidth)
            if let number {
                Text("\(number)")
                    .font(.frmrMeta.weight(.bold))
                    .foregroundStyle(.white)
                    .frmrChromeTypeSize()
            }
        }
        .frame(width: Constants.RollUI.selectionBadgeSize, height: Constants.RollUI.selectionBadgeSize)
        .opacity(isVisible ? 1 : 0)
        .accessibilityHidden(true)
    }
}

private struct EmptyRollView: View {
    let theme: ThemePalette
    let onTakePhoto: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Your roll is empty", systemImage: "camera.aperture")
                .font(.frmrReading.weight(.semibold))
        } description: {
            Text("Photos you save from the camera land here, ready to edit again.")
                .font(.frmrMeta)
        } actions: {
            Button("Take a photo", action: onTakePhoto)
                .frmrPrimaryButtonStyle()
                .accessibilityHint("Opens the camera")
                .accessibilityIdentifier("roll.takePhoto")
        }
        .foregroundStyle(theme.textMuted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roll.empty")
    }
}
