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
    private var accent: Color { ThemePalette.accent(for: colorScheme) }
    private var hasEntriesToday: Bool {
        entries.contains { Calendar.current.isDateInToday($0.createdAt) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlassSegmentedControl(
                    segments: LibraryView.Section.allCases.map {
                        .init(value: $0, title: $0.label, identifier: "library.tab.\($0.label.lowercased())")
                    },
                    selection: section,
                    accent: accent,
                    onSelect: { selected in
                        switch selected {
                        case .roll: viewModel.selectRollTab()
                        case .entries: viewModel.selectEntriesTab()
                        case .strips: viewModel.selectStripsTab()
                        }
                    }
                )
                .padding(.horizontal, Constants.LibraryUI.listHorizontalPadding)
                .padding(.top, Constants.LibraryUI.segmentedTopPadding)
                .padding(.bottom, Constants.LibraryUI.segmentedBottomPadding)
                content
            }
            .background(theme.background)
            .navigationTitle("Library")
            .tint(accent)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Diary strips are compiled only on this explicit tap
                    if section == .entries {
                        Button("Make today's strip", action: compileToday)
                            .disabled(!hasEntriesToday)
                            .accessibilityIdentifier("library.makeTodaysStrip")
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

private struct StripsList: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \DailyStrip.createdAt, order: .reverse) private var strips: [DailyStrip]
    @State private var selectedStrip: DailyStrip?

    let viewModel: LibraryViewModel

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.LibraryUI.stripColumnSpacing, alignment: .top),
        count: Constants.LibraryUI.stripColumns
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Constants.LibraryUI.stripRowSpacing) {
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
                    .accessibilityLabel("Strip from \(strip.createdAt.librarySectionTitle)")
                    .accessibilityHint("Opens the strip")
                    .accessibilityIdentifier("library.strip")
                }
            }
            .padding(.horizontal, Constants.LibraryUI.listHorizontalPadding)
        }
        .frmrTabBarScrollInsets()
        .background(theme.background)
        .overlay {
            if strips.isEmpty {
                LibraryEmptyState(
                    systemImage: "film",
                    title: "No strips yet",
                    message: "Compile today's entries, or use film strip mode.",
                    color: theme.muted
                )
            }
        }
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
                .font(.caption.weight(.medium))
                .foregroundStyle(textColor)
        }
        .frame(maxWidth: .infinity)
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
                .clipShape(RoundedRectangle(cornerRadius: Constants.LibraryUI.stripCornerRadius))
                .shadow(
                    color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                    radius: Constants.StripUI.previewShadowRadius / 2
                )
        }
    }
}

// Quiet empty state shared by the Library's tabs: icon, title, one line
struct LibraryEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        VStack(spacing: Constants.LibraryUI.emptySpacing) {
            Image(systemName: systemImage)
                .font(.system(size: Constants.LibraryUI.emptyIconSize, weight: .light))
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.medium))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(color)
        .padding()
        .accessibilityElement(children: .combine)
    }
}
