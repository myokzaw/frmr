import Foundation

// nonisolated: pure formatting, used by the off-main-actor strip renderer
nonisolated extension Date {
    // Section headers in the library: "Today", "Yesterday", then full dates
    var librarySectionTitle: String {
        if Calendar.current.isDateInToday(self) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        }
        return formatted(date: .abbreviated, time: .omitted)
    }

    // Date stamp printed at the bottom of a rendered strip
    var stripDateStamp: String {
        formatted(date: .abbreviated, time: .omitted).uppercased()
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    // Timestamp shown in the full-screen entry viewer
    var entryDetailTimestamp: String {
        formatted(date: .long, time: .shortened)
    }
}
