import SwiftData
import SwiftUI

// Library (project.md §2, screen 5; v5 F6; v5.2 M6): Roll (the default),
// Entries and Strips, switched by a system segmented control in the
// navigation bar's principal slot (no large title). Each tab owns its
// trailing toolbar actions, hidden (not disabled) when they don't apply.
struct LibraryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(ErrorState.self) private var errorState
    @State private var viewModel = LibraryViewModel()

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }

    var body: some View {
        NavigationStack {
            content
                .background(theme.bg.ignoresSafeArea())
                .navigationTitle(viewModel.tab.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Library", selection: $viewModel.tab) {
                            ForEach(LibraryViewModel.Tab.allCases, id: \.self) { section in
                                Text(section.label)
                                    .accessibilityIdentifier("library.tab.\(section.label.lowercased())")
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityIdentifier("library.tabs")
                    }
                }
                .tint(theme.tint)
        }
        .task {
            viewModel.errorState = errorState
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.tab {
        case .roll: RollView()
        case .entries: DiaryView()
        case .strips: StripsList(viewModel: viewModel)
        }
    }
}

// v5.2 M6: strips in two columns, each drawn at the column width with its
// date below. "+" makes today's strip from the diary (moved from Entries:
// it is a strip action), shown only when there are entries from today.
private struct StripsList: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Query(sort: \DailyStrip.createdAt, order: .reverse) private var strips: [DailyStrip]
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var selectedStrip: DailyStrip?

    @Bindable var viewModel: LibraryViewModel

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }
    private var hasEntriesToday: Bool { LibraryViewModel.hasEntriesToday(in: entries) }

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
                        StripTile(
                            image: LibraryViewModel.loadStripImage(for: strip),
                            dateText: strip.createdAt.librarySectionTitle,
                            textColor: theme.textMuted
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Strip from \(strip.createdAt.librarySectionTitle)")
                    .accessibilityHint("Opens the strip")
                    .accessibilityIdentifier("library.strip")
                }
            }
            .padding(.horizontal, Constants.DesignUI.gutter)
            .padding(.top, Constants.DesignUI.Space.l)
        }
        .frmrTabBarScrollInsets()
        .overlay {
            if strips.isEmpty {
                ContentUnavailableView {
                    Label("No strips yet", systemImage: "film.stack")
                        .font(.frmrReading.weight(.semibold))
                } description: {
                    Text("Use Film strip mode on the camera, or make today's strip from your entries.")
                        .font(.frmrMeta)
                }
                .foregroundStyle(theme.textMuted)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if hasEntriesToday {
                    // Diary strips are compiled only on this explicit tap
                    Button {
                        viewModel.isCompileStripPresented = true
                    } label: {
                        Label("Make today's strip", systemImage: "plus")
                    }
                    .accessibilityHint("Builds a strip from today's diary entries")
                    .accessibilityIdentifier("library.makeTodaysStrip")
                }
            }
        }
        .fullScreenCover(item: $selectedStrip) { strip in
            StripDetailView(
                image: LibraryViewModel.loadStripImage(for: strip),
                dateText: strip.createdAt.librarySectionTitle,
                onSaveToCameraRoll: { Task { await viewModel.saveStripToCameraRoll(strip) } }
            )
        }
        .fullScreenCover(isPresented: $viewModel.isCompileStripPresented) {
            StripView(items: LibraryViewModel.todaysItems(from: entries), isPhotobooth: false)
        }
    }
}

private struct StripTile: View {
    let image: UIImage?
    let dateText: String
    let textColor: Color

    var body: some View {
        VStack(spacing: Constants.DesignUI.Space.s) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
                    .shadow(
                        color: .black.opacity(Constants.StripUI.previewShadowOpacity),
                        radius: Constants.StripUI.previewShadowRadius / 2
                    )
            }
            Text(dateText)
                .font(.frmrMeta)
                .foregroundStyle(textColor)
        }
        .frame(maxWidth: .infinity)
    }
}
