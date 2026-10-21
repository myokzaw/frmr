import SwiftData
import SwiftUI

// Library (project.md §2, screen 5; v5 F6): Roll tab (Photo-mode shots,
// the default), Entries tab (the diary list) and Strips tab, plus the
// explicit "compile today's entries into a strip" action.
struct LibraryView: View {
    enum Section: CaseIterable {
        case roll
        case entries
        case strips

        var label: String {
            switch self {
            case .roll: return "Roll"
            case .entries: return "Entries"
            case .strips: return "Strips"
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ErrorState.self) private var errorState
    @State private var viewModel = LibraryViewModel()
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]

    private var section: Section {
        switch viewModel.tab {
        case .roll: return .roll
        case .entries: return .entries
        case .strips: return .strips
        }
    }
    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }
    private var hasEntriesToday: Bool {
        entries.contains { Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LibraryTabRow(
                    selected: section,
                    activeColor: theme.primary,
                    inactiveColor: theme.muted,
                    onSelect: { selected in
                        switch selected {
                        case .roll: viewModel.selectRollTab()
                        case .entries: viewModel.selectEntriesTab()
                        case .strips: viewModel.selectStripsTab()
                        }
                    }
                )
                content
            }
            .background(theme.background)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Diary strips are compiled only on this explicit tap
                    if section == .entries {
                        Button("Make today's strip", action: compileToday)
                            .disabled(!hasEntriesToday)
                    }
                }
            }
        }
        .task {
            viewModel.errorState = errorState
        }
        .fullScreenCover(isPresented: Bindable(viewModel).isCompileStripPresented.projectedValue) {
            StripView(items: LibraryViewModel.todaysItems(from: entries), isPhotobooth: false)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .roll: RollView()
        case .entries: DiaryView()
        case .strips: StripsList(viewModel: viewModel)
        }
    }

    private func compileToday() {
        viewModel.isCompileStripPresented = true
    }
}

private struct LibraryTabRow: View {
    let selected: LibraryView.Section
    let activeColor: Color
    let inactiveColor: Color
    let onSelect: (LibraryView.Section) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryView.Section.allCases, id: \.self) { section in
                LibraryTab(
                    label: section.label,
                    isActive: section == selected,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    action: { onSelect(section) }
                )
            }
        }
        .padding(.horizontal)
    }
}

private struct LibraryTab: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    let action: () -> Void

    private var textColor: Color { isActive ? activeColor : inactiveColor }
    private var fontWeight: Font.Weight { isActive ? .semibold : .medium }
    private var underline: Color { isActive ? activeColor : .clear }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: Constants.LibraryUI.tabFontSize, weight: fontWeight))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Constants.CameraUI.chipVerticalPadding)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(underline)
                        .frame(height: Constants.StripUI.swatchBorderWidth)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("library.tab.\(label.lowercased())")
    }
}

private struct StripsList: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \DailyStrip.createdAt, order: .reverse) private var strips: [DailyStrip]
    @State private var selectedStrip: DailyStrip?

    let viewModel: LibraryViewModel

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Constants.LibraryUI.rowSpacing) {
                ForEach(strips) { strip in
                    Button {
                        selectedStrip = strip
                    } label: {
                        StripRow(
                            image: LibraryViewModel.loadStripImage(for: strip),
                            dateText: strip.createdAt.librarySectionTitle,
                            textColor: theme.muted
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.strip")
                }
            }
            .padding()
        }
        .overlay(EmptyStripsHint(isVisible: strips.isEmpty, color: theme.muted))
        .fullScreenCover(item: $selectedStrip) { strip in
            StripDetailView(
                image: LibraryViewModel.loadStripImage(for: strip),
                dateText: strip.createdAt.librarySectionTitle,
                onSaveToCameraRoll: { Task { await viewModel.saveStripToCameraRoll(strip) } }
            )
        }
    }
}

private struct StripRow: View {
    let image: UIImage?
    let dateText: String
    let textColor: Color

    var body: some View {
        VStack(spacing: Constants.Strip.captionSpacing) {
            StripThumbnail(image: image)
            Text(dateText)
                .font(.system(size: Constants.LibraryUI.sectionFontSize, weight: .semibold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(textColor)
        }
    }
}

private struct StripThumbnail: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: Constants.LibraryUI.stripThumbnailHeight)
                .shadow(
                    color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                    radius: Constants.StripUI.previewShadowRadius / 2
                )
        }
    }
}

private struct EmptyStripsHint: View {
    let isVisible: Bool
    let color: Color

    var body: some View {
        Text("No strips yet. Compile today's entries or use film strip mode.")
            .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
            .italic()
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding()
            .opacity(isVisible ? 1 : 0)
    }
}
