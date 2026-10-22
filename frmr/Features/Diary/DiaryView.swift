import SwiftData
import SwiftUI

// Diary entry list grouped by date, embedded in the Library's Entries tab
// (v5.1 F10): a quiet list, each row a thumbnail in the entry's own look
// beside its excerpt and time.
struct DiaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var selectedEntry: DiaryEntry?

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }
    private var sections: [DiaryViewModel.DaySection] { DiaryViewModel.groupByDay(entries) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(theme.muted)
                        .padding(.top, Constants.LibraryUI.sectionTopSpacing)
                        .padding(.bottom, Constants.LibraryUI.rowVerticalPadding)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.entries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            EntryRow(
                                entry: entry,
                                excerpt: entry.response.isEmpty ? entry.prompt : entry.response,
                                prompt: entry.response.isEmpty ? "" : entry.prompt,
                                timeText: entry.createdAt.formatted(date: .omitted, time: .shortened),
                                textColor: theme.text,
                                mutedColor: theme.muted
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the entry")
                        .accessibilityIdentifier("library.entry")
                    }
                }
            }
            .padding(.horizontal, Constants.LibraryUI.listHorizontalPadding)
        }
        .frmrTabBarScrollInsets()
        .background(theme.background)
        .overlay {
            if entries.isEmpty {
                LibraryEmptyState(
                    systemImage: "book.closed",
                    title: "No entries yet",
                    message: "Take a photo, then choose Continue to diary to write about it.",
                    color: theme.muted
                )
            }
        }
        .fullScreenCover(item: $selectedEntry) { entry in
            EntryDetailView(
                entry: entry,
                prompt: entry.prompt,
                response: entry.response,
                dateText: entry.createdAt.entryDetailTimestamp
            )
        }
    }
}

private struct EntryRow: View {
    let entry: DiaryEntry
    let excerpt: String
    let prompt: String
    let timeText: String
    let textColor: Color
    let mutedColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: Constants.LibraryUI.rowSpacing) {
            Thumbnail(entry: entry)
            VStack(alignment: .leading, spacing: 4) {
                Text(excerpt)
                    .font(.callout)
                    .foregroundStyle(textColor)
                    .lineLimit(Constants.LibraryUI.excerptLineLimit)
                    .multilineTextAlignment(.leading)
                if !prompt.isEmpty {
                    Text(prompt)
                        .font(.caption)
                        .foregroundStyle(mutedColor)
                        .lineLimit(1)
                }
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(mutedColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Constants.LibraryUI.rowVerticalPadding)
        .contentShape(Rectangle())
    }
}

// v4 F11: the thumbnail shows the entry in its own stock
private struct Thumbnail: View {
    let entry: DiaryEntry

    var body: some View {
        Color.appBlack.opacity(Constants.Strip.emptySlotAlpha)
            .frame(width: Constants.LibraryUI.thumbnailSize, height: Constants.LibraryUI.thumbnailSize)
            .overlay(EntryLookImage(entry: entry, contentMode: .fill) { EmptyView() })
            .clipShape(RoundedRectangle(cornerRadius: Constants.LibraryUI.thumbnailCornerRadius))
            .accessibilityHidden(true)
    }
}
