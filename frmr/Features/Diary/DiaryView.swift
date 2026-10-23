import SwiftData
import SwiftUI

// The Library's Entries tab (v5.1 F10, v5.2 M6): entries grouped by day,
// each row led by the user's own words (serif, two lines), then the prompt
// they answered (muted italic) and when / on what film. A 4:5 thumbnail in
// the entry's own look sits beside it.
struct DiaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var selectedEntry: DiaryEntry?

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }
    private var sections: [DiaryViewModel.DaySection] { DiaryViewModel.groupByDay(entries) }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            EntryRow(
                                entry: entry,
                                excerpt: LibraryViewModel.excerpt(for: entry),
                                prompt: entry.response.isEmpty ? "" : entry.prompt,
                                metadata: LibraryViewModel.metadataLine(for: entry),
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.bg)
                        .accessibilityHint("Opens the entry")
                        .accessibilityIdentifier("library.entry")
                    }
                } header: {
                    Text(section.title)
                        .font(.frmrLabel.weight(.semibold))
                        .foregroundStyle(theme.text)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frmrTabBarScrollInsets()
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No entries yet", systemImage: "book.closed")
                        .font(.frmrReading.weight(.semibold))
                } description: {
                    Text("Take a photo, then choose Continue to diary to write about it.")
                        .font(.frmrMeta)
                }
                .foregroundStyle(theme.textMuted)
            }
        }
        .fullScreenCover(item: $selectedEntry) { entry in
            EntryDetailView(
                entry: entry,
                prompt: entry.prompt,
                response: entry.response,
                metadata: LibraryViewModel.metadataLine(for: entry)
            )
        }
    }
}

private struct EntryRow: View {
    let entry: DiaryEntry
    let excerpt: String
    /// The prompt as a second line, or empty when it is already the excerpt.
    let prompt: String
    let metadata: String
    let theme: ThemePalette

    var body: some View {
        HStack(alignment: .top, spacing: Constants.DesignUI.Space.m) {
            Thumbnail(entry: entry)
            VStack(alignment: .leading, spacing: Constants.DesignUI.Space.xs) {
                Text(excerpt.isEmpty ? "No words yet" : excerpt)
                    .font(.frmrReading)
                    .foregroundStyle(excerpt.isEmpty ? theme.textMuted : theme.text)
                    .lineLimit(Constants.LibraryUI.excerptLineLimit)
                    .multilineTextAlignment(.leading)
                if !prompt.isEmpty {
                    Text(prompt)
                        .font(.frmrMeta.italic())
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                }
                Text(metadata)
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Constants.DesignUI.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// v4 F11: the thumbnail shows the entry in its own stock
private struct Thumbnail: View {
    let entry: DiaryEntry

    var body: some View {
        Color.appBlack.opacity(Constants.Strip.emptySlotAlpha)
            .frame(width: Constants.LibraryUI.thumbnailWidth, height: Constants.LibraryUI.thumbnailWidth / Constants.CameraUI.stripFrameAspect)
            .overlay(EntryLookImage(entry: entry, contentMode: .fill) { EmptyView() })
            .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
            .accessibilityHidden(true)
    }
}
