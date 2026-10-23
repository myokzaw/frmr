import Foundation
import Observation
import SwiftData
import UIKit

@Observable
final class DiaryViewModel {
    var errorState: ErrorState?

    private(set) var prompt: String = ""
    private var lastPromptIndex: Int?

    // Hard limit enforced here so the view never holds an over-long draft
    var responseText = "" {
        didSet {
            if responseText.count > Constants.entryCharacterLimit {
                responseText = String(responseText.prefix(Constants.entryCharacterLimit))
            }
        }
    }

    var characterCountText: String {
        "\(responseText.count)/\(Constants.entryCharacterLimit)"
    }

    var isCharacterCountVisible: Bool {
        responseText.count >= Constants.promptSoftLimit
    }

    func prepareNewEntry() {
        responseText = ""
        let index = Self.nextPromptIndex(excluding: lastPromptIndex, count: PromptBank.all.count)
        lastPromptIndex = index
        prompt = PromptBank.all[index]
    }

    // OPEN: repeat strategy TBD (project.md §13 #4 suggests full shuffle before
    // repeat) — conservative default is random with no immediate repeat.
    static func nextPromptIndex(excluding lastIndex: Int?, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var index = Int.random(in: 0..<count)
        if index == lastIndex {
            index = (index + 1) % count
        }
        return index
    }

    /// Returns true when the entry was persisted and the editor can close.
    ///
    /// With `rollPhotoID` (v5.1 F4/F5) the entry LINKS to that Roll photo:
    /// no image is copied, and `image`/`filmStock`/`look`/`capturedAt` are
    /// ignored — the Roll photo's file, look and capture date are used.
    /// Without it (entries from before v5.1) `image` is the original
    /// development, copied to the diary's own file; `filmStock`/`look` are
    /// stored beside it and applied only on display (v4 F11, non-destructive).
    func saveEntry(
        image: UIImage?,
        filmStock: StripCustomization.FilmStock = .none,
        look: FilmLook? = nil,
        capturedAt: Date? = nil,
        rollPhotoID: UUID? = nil,
        includeText: Bool,
        context: ModelContext
    ) -> Bool {
        do {
            let entry: DiaryEntry
            if let rollPhotoID {
                guard let photo = try RollViewModel.photo(withID: rollPhotoID, context: context) else {
                    errorState?.raise(.persistenceFailed(reason: "The photo for this entry is no longer in the Roll."))
                    return false
                }
                entry = DiaryEntry(
                    photoPath: photo.photoPath,
                    prompt: prompt,
                    response: includeText ? responseText : "",
                    capturedAt: photo.capturedAt,
                    look: photo.look,
                    rollPhotoID: photo.id
                )
            } else {
                guard let image else {
                    errorState?.raise(.persistenceFailed(reason: "There's no photo to save."))
                    return false
                }
                entry = DiaryEntry(
                    photoPath: try savePhotoFile(image),
                    prompt: prompt,
                    response: includeText ? responseText : "",
                    filmStock: filmStock,
                    capturedAt: capturedAt,
                    look: look
                )
            }
            context.insert(entry)
            try context.save()
            return true
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
    }

    static func groupByDay(_ entries: [DiaryEntry]) -> [DaySection] {
        let grouped = Dictionary(grouping: entries) { $0.createdAt.startOfDay }
        return grouped
            .sorted { $0.key > $1.key }
            .map { day, dayEntries in
                DaySection(
                    day: day,
                    title: day.librarySectionTitle,
                    entries: dayEntries.sorted { $0.createdAt > $1.createdAt }
                )
            }
    }

    static func loadPhoto(for entry: DiaryEntry) -> UIImage? {
        UIImage(contentsOfFile: FileManager.documentsURL(forRelativePath: entry.photoPath).path())
    }

    // MARK: Display in the entry's stock (v4 F11)

    /// An entry's photo through its own stock, sized for a view of `size`
    /// points at `scale`. Renders off the main actor and caches in memory
    /// by (entry, stock, pixel size); old entries (no stock) are Off and
    /// get the original file. nil when the photo can't be read.
    static func displayImage(for entry: DiaryEntry, size: CGSize, scale: CGFloat) async -> UIImage? {
        let id = entry.id
        let look = entry.look
        let seed = StripGenerator.photoLookSeed(for: entry.lookSeedDate)
        let url = FileManager.documentsURL(forRelativePath: entry.photoPath)
        let pixels = pixelSize(size, scale: scale)
        return await FilmLookCache.shared.displayImage(id: id, look: look, seed: seed, url: url, pixelSize: pixels)
    }

    /// The cached display image if one is ready, so a view can show it on
    /// its first frame instead of flashing a placeholder.
    static func cachedDisplayImage(for entry: DiaryEntry, size: CGSize, scale: CGFloat) -> UIImage? {
        FilmLookCache.shared.cachedImage(id: entry.id, look: entry.look, pixelSize: pixelSize(size, scale: scale))
    }

    nonisolated static func pixelSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    struct DaySection: Identifiable {
        let day: Date
        let title: String
        let entries: [DiaryEntry]
        var id: Date { day }
    }

    private func savePhotoFile(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: CGFloat(Constants.jpegCompressionQuality)) else {
            throw AppError.persistenceFailed(reason: "The photo couldn't be encoded.")
        }
        let directory = try FileManager.createPhotosDirectory()
        let filename = UUID().uuidString + ".jpg"
        try data.write(to: directory.appending(path: filename))
        return "Photos/" + filename
    }
}
