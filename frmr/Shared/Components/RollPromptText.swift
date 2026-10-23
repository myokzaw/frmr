import Foundation

// The delete and Clear roll questions (v5.1-7/12), shared by the Roll, the
// editor and Settings. `linkedEntries` nil means the count couldn't be read
// (v5.2, BUG-V51-03): the question then offers both answers, because reading
// a failed fetch as "no entries" could delete entries without saying so.
nonisolated enum RollPromptText {
    static func deleteTitle(photoCount: Int, linkedEntries: Int?) -> String {
        let photoText = photoCount == 1 ? "this photo" : "these \(photoCount) photos"
        switch linkedEntries {
        case 0:
            return "Delete \(photoText)? This can't be undone."
        case nil:
            return "Diary entries may be about \(photoText). Delete them too, or keep them with their own copy of the photo?"
        case let count?:
            return "\(entryPhrase(count)) about \(photoText). Delete the entries too, or keep them with their own copy of the photo?"
        }
    }

    static func clearRollTitle(linkedEntries: Int?) -> String {
        switch linkedEntries {
        case 0:
            return "Delete every photo in your roll? This can't be undone."
        case nil:
            return "Diary entries may be about photos in your roll. Delete them too, or keep them with their own copy of the photo?"
        case let count?:
            return "\(entryPhrase(count)) about photos in your roll. Delete them too, or keep them with their own copy of the photo?"
        }
    }

    /// Whether the question offers Keep and Delete-both (anything but a known zero).
    static func asksAboutEntries(_ linkedEntries: Int?) -> Bool {
        linkedEntries != 0
    }

    private static func entryPhrase(_ count: Int) -> String {
        count == 1 ? "1 diary entry is" : "\(count) diary entries are"
    }
}
