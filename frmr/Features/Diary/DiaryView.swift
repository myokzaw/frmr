import SwiftData
import SwiftUI

// Diary entry list grouped by date. Embedded in the Library's Entries tab.
struct DiaryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \DiaryEntry.createdAt, order: .reverse) private var entries: [DiaryEntry]
    @State private var selectedEntry: DiaryEntry?

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }
    private var sections: [DiaryViewModel.DaySection] { DiaryViewModel.groupByDay(entries) }

    var body: some View {
        List(sections) { section in
            Section {
                ForEach(section.entries) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        EntryRow(
                            entry: entry,
                            excerpt: entry.response.isEmpty ? entry.prompt : entry.response,
                            textColor: theme.text
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(section.title)
                    .font(.system(size: Constants.LibraryUI.sectionFontSize, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(1)
                    .foregroundStyle(theme.muted)
            }
            .listRowBackground(theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .overlay(EmptyDiaryHint(isVisible: entries.isEmpty, color: theme.muted))
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
    let textColor: Color

    var body: some View {
        HStack(spacing: Constants.LibraryUI.rowSpacing) {
            Thumbnail(entry: entry)
            Text(excerpt)
                .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
                .italic()
                .foregroundStyle(textColor)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
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
    }
}

private struct EmptyDiaryHint: View {
    let isVisible: Bool
    let color: Color

    var body: some View {
        Text("No entries yet. Take a photo to start your journal.")
            .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
            .italic()
            .foregroundStyle(color)
            .opacity(isVisible ? 1 : 0)
    }
}
