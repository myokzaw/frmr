import Foundation
import Observation
import Photos
import SwiftData
import UIKit

/// One day of the Roll (v5.2 M6): a "contact sheet".
struct RollDaySection: Identifiable {
    /// Start of the day.
    let id: Date
    /// "Today", "Yesterday", then the date.
    let title: String
    /// Newest first.
    let photos: [RollPhoto]
}

/// The Roll (v5 F6): newest-first listing, saving, re-editing, deleting,
/// exporting to Photos and selecting photos for a strip.
///
/// The list itself comes from the view's `@Query`; the order and everything
/// else that has a rule lives here as pure statics so it is unit-testable.
/// Nothing leaves the app except an explicit export.
@Observable
final class RollViewModel {
    var errorState: ErrorState?

    // MARK: Selection (multi-select export, and picking photos for a strip)

    private(set) var selectedIDs: [UUID] = []
    var isSelecting = false
    private(set) var isExporting = false
    /// How many photos the last export saved; 0 until one finishes.
    private(set) var lastExportCount = 0

    var selectionCount: Int { selectedIDs.count }
    var hasSelection: Bool { !selectedIDs.isEmpty }

    func isSelected(_ photo: RollPhoto) -> Bool { selectedIDs.contains(photo.id) }

    /// Taps a photo in select mode. `limit` caps the selection (the strip
    /// picker passes `Constants.Roll.maxPhotosPerStrip`); a tap past it is
    /// ignored. Selection keeps tap order, which is the strip's frame order.
    @discardableResult
    func toggleSelection(of photo: RollPhoto, limit: Int? = nil) -> Bool {
        if let index = selectedIDs.firstIndex(of: photo.id) {
            selectedIDs.remove(at: index)
            return true
        }
        if let limit, selectedIDs.count >= limit { return false }
        selectedIDs.append(photo.id)
        return true
    }

    func clearSelection() {
        selectedIDs = []
    }

    func endSelecting() {
        isSelecting = false
        selectedIDs = []
    }

    /// The selected photos, in selection order; photos deleted since are skipped.
    func selectedPhotos(in photos: [RollPhoto]) -> [RollPhoto] {
        let byID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selectedIDs.compactMap { byID[$0] }
    }

    // MARK: Listing

    /// Newest capture first; ties by the later edit, then id, so the order
    /// is total and a re-edit never shuffles unrelated photos.
    static func sorted(_ photos: [RollPhoto]) -> [RollPhoto] {
        photos.sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt { return lhs.capturedAt > rhs.capturedAt }
            if lhs.editedAt != rhs.editedAt { return lhs.editedAt > rhs.editedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The photos grouped by the day they were taken, newest day first and
    /// newest photo first within it (v5.2 M6).
    static func daySections(_ photos: [RollPhoto]) -> [RollDaySection] {
        let grouped = Dictionary(grouping: sorted(photos)) { $0.capturedAt.startOfDay }
        return grouped.keys.sorted(by: >).map { day in
            RollDaySection(id: day, title: day.librarySectionTitle, photos: grouped[day] ?? [])
        }
    }

    static func loadPhoto(for photo: RollPhoto) -> UIImage? {
        UIImage(contentsOfFile: FileManager.documentsURL(forRelativePath: photo.photoPath).path())
    }

    // MARK: Saving, editing, deleting

    /// Stores a new Roll photo: the original as a file, its look as a row.
    /// The look can be edited later; the file is never changed. Throws
    /// `AppError`.
    @discardableResult
    static func insert(
        original: UIImage,
        look: FilmLook,
        capturedAt: Date,
        context: ModelContext,
        now: Date = .now
    ) throws -> RollPhoto {
        guard let data = original.jpegData(compressionQuality: CGFloat(Constants.PhotoEdit.rollPhotoJPEGQuality)) else {
            throw AppError.persistenceFailed(reason: "The photo couldn't be encoded.")
        }
        let path: String
        do {
            let directory = try FileManager.createRollDirectory()
            let filename = UUID().uuidString + ".jpg"
            try data.write(to: directory.appending(path: filename))
            path = Constants.Roll.photosDirectoryName + "/" + filename
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
        let photo = RollPhoto(capturedAt: capturedAt, photoPath: path, look: look, editedAt: now)
        context.insert(photo)
        do {
            try context.save()
        } catch {
            // No row to point at the file: do not leave it orphaned
            removeFile(at: path)
            context.delete(photo)
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
        return photo
    }

    /// Re-edit save: replaces the look, never the original. Diary entries
    /// linked to the photo follow (v5.1-3 live link): their mirrored look is
    /// updated in the same save.
    static func update(_ photo: RollPhoto, look: FilmLook, context: ModelContext, now: Date = .now) throws {
        photo.look = look
        photo.editedAt = now
        for entry in try linkedEntries(for: photo, context: context) {
            entry.look = look
        }
        do {
            try context.save()
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    // MARK: Diary links (v5.1 F7, v5.1-7)

    /// What to do with diary entries linked to a Roll photo being deleted.
    enum RollDeletion: Equatable {
        /// Remove the entries and the photo.
        case deleteBoth
        /// Give each entry its own copy of the photo (current look
        /// snapshotted into the entry), then delete the Roll photo.
        case keepEntry
    }

    static func photo(withID id: UUID, context: ModelContext) throws -> RollPhoto? {
        var descriptor = FetchDescriptor<RollPhoto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    /// The entries that link to `photo`.
    static func linkedEntries(for photo: RollPhoto, context: ModelContext) throws -> [DiaryEntry] {
        let id: UUID? = photo.id
        do {
            return try context.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.rollPhotoID == id }))
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    /// For the delete prompt: how many entries a delete would touch. A failed
    /// fetch reads as 0 (and is logged); prompts that must not under-warn use
    /// `linkedEntryCountIfKnown(for:in:)`.
    static func linkedEntryCount(for photo: RollPhoto, in context: ModelContext) -> Int {
        linkedEntryCountIfKnown(for: photo, in: context) ?? 0
    }

    /// For the Clear roll prompt: entries linked to any Roll photo. Same
    /// failure behaviour as above (`linkedEntryCountIfKnown(in:)`).
    static func linkedEntryCount(in context: ModelContext) -> Int {
        linkedEntryCountIfKnown(in: context) ?? 0
    }

    /// Like `linkedEntryCount(for:in:)` but nil when the fetch fails, so the
    /// caller can ask conservatively instead of reading failure as "none".
    static func linkedEntryCountIfKnown(for photo: RollPhoto, in context: ModelContext) -> Int? {
        let id: UUID? = photo.id
        return knownCount(describing: "photo \(photo.id)") {
            try context.fetchCount(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.rollPhotoID == id }))
        }
    }

    /// Like `linkedEntryCount(in:)` but nil when the fetch fails.
    static func linkedEntryCountIfKnown(in context: ModelContext) -> Int? {
        knownCount(describing: "the Roll") {
            try context.fetchCount(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.rollPhotoID != nil }))
        }
    }

    /// Runs a count fetch: the number, or nil with the failure logged.
    static func knownCount(describing subject: String, _ fetch: () throws -> Int) -> Int? {
        do {
            return try fetch()
        } catch {
            print("[RollViewModel] Linked-entry count failed for \(subject): \(error)")
            return nil
        }
    }

    /// The badge lookup (v5.1-6), one fetch for the whole grid: ids of
    /// every Roll photo that has at least one entry.
    static func photoIDsWithDiaryEntry(in context: ModelContext) -> Set<UUID> {
        let entries = (try? context.fetch(FetchDescriptor<DiaryEntry>(predicate: #Predicate { $0.rollPhotoID != nil }))) ?? []
        return linkedPhotoIDs(in: entries)
    }

    /// The same set from entries a view already has (`@Query`), no fetch.
    static func linkedPhotoIDs(in entries: [DiaryEntry]) -> Set<UUID> {
        Set(entries.compactMap(\.rollPhotoID))
    }

    static func hasDiaryEntry(_ photo: RollPhoto, in context: ModelContext) -> Bool {
        linkedEntryCount(for: photo, in: context) > 0
    }

    /// Deletes the record and its file. Linked diary entries are handled
    /// per `entries` (default `.keepEntry`: an entry is never lost silently).
    static func delete(_ photo: RollPhoto, entries: RollDeletion = .keepEntry, context: ModelContext) throws {
        let path = photo.photoPath
        var copies: [String] = []
        do {
            try applyDeletion(entries, to: photo, context: context, copies: &copies)
            context.delete(photo)
            try context.save()
        } catch {
            for copy in copies { removeFile(at: copy) }
            context.rollback()
            throw (error as? AppError) ?? AppError.persistenceFailed(reason: error.localizedDescription)
        }
        removeFile(at: path)
    }

    /// "Clear roll" (OPEN: v5-7): every Roll photo and its file. Strips are
    /// untouched. Linked diary entries follow `entries` — default
    /// `.keepEntry` (OPEN: v5.1-12): each keeps its own copy of the photo.
    static func clearRoll(entries: RollDeletion = .keepEntry, context: ModelContext) throws {
        let photos = try context.fetch(FetchDescriptor<RollPhoto>())
        let paths = photos.map(\.photoPath)
        var copies: [String] = []
        do {
            for photo in photos {
                try applyDeletion(entries, to: photo, context: context, copies: &copies)
                context.delete(photo)
            }
            try context.save()
        } catch {
            for copy in copies { removeFile(at: copy) }
            context.rollback()
            throw (error as? AppError) ?? AppError.persistenceFailed(reason: error.localizedDescription)
        }
        for path in paths { removeFile(at: path) }
    }

    private static func applyDeletion(
        _ choice: RollDeletion, to photo: RollPhoto, context: ModelContext, copies: inout [String]
    ) throws {
        let linked = try linkedEntries(for: photo, context: context)
        guard !linked.isEmpty else { return }
        switch choice {
        case .deleteBoth:
            for entry in linked { context.delete(entry) }
        case .keepEntry:
            // One copy is enough for several entries of the same photo
            let copyPath = try copyToDiaryStorage(photo)
            copies.append(copyPath)
            for entry in linked {
                entry.photoPath = copyPath
                entry.look = photo.look
                entry.capturedAt = photo.capturedAt
                entry.rollPhotoID = nil
            }
        }
    }

    /// Copies the Roll file into the diary's own storage; returns the
    /// relative path. Throws `AppError`.
    private static func copyToDiaryStorage(_ photo: RollPhoto) throws -> String {
        do {
            let directory = try FileManager.createPhotosDirectory()
            let filename = UUID().uuidString + ".jpg"
            try FileManager.default.copyItem(
                at: FileManager.documentsURL(forRelativePath: photo.photoPath),
                to: directory.appending(path: filename)
            )
            return "Photos/" + filename
        } catch {
            throw AppError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    /// A missing file is already the desired state; any other failure is
    /// logged (the record is gone, so the user can't act on an orphan).
    private static func removeFile(at relativePath: String) {
        let url = FileManager.documentsURL(forRelativePath: relativePath)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            print("[RollViewModel] Could not remove \(relativePath): \(error)")
        }
    }

    // MARK: Display

    /// A Roll photo through its current look, sized for a view of `size`
    /// points at `scale`; rendered off the main actor and cached by
    /// (photo, look, pixel size). nil when the file can't be read.
    static func displayImage(for photo: RollPhoto, size: CGSize, scale: CGFloat) async -> UIImage? {
        let id = photo.id
        let look = photo.look
        let seed = StripGenerator.photoLookSeed(for: photo.lookSeedDate)
        let url = FileManager.documentsURL(forRelativePath: photo.photoPath)
        let pixels = DiaryViewModel.pixelSize(size, scale: scale)
        return await FilmLookCache.shared.displayImage(id: id, look: look, seed: seed, url: url, pixelSize: pixels)
    }

    static func cachedDisplayImage(for photo: RollPhoto, size: CGSize, scale: CGFloat) -> UIImage? {
        FilmLookCache.shared.cachedImage(
            id: photo.id, look: photo.look, pixelSize: DiaryViewModel.pixelSize(size, scale: scale)
        )
    }

    // MARK: Export (explicit user action only)

    /// Saves each photo to Photos as a full-resolution HEIC in its current
    /// look. One library change for the whole selection. Raises `AppError`
    /// and saves nothing if any photo can't be read or rendered.
    ///
    /// - Parameter savePhotosData: where the encoded files go; Photos, or
    ///   a stub in tests.
    func export(
        _ photos: [RollPhoto],
        savePhotosData: @escaping @Sendable ([Data]) async throws -> Void = { try await PHPhotoLibrary.saveToCameraRoll(photosData: $0) }
    ) async {
        guard !isExporting, !photos.isEmpty else { return }
        isExporting = true
        lastExportCount = 0
        defer { isExporting = false }

        let jobs = photos.map { photo in
            ExportJob(
                url: FileManager.documentsURL(forRelativePath: photo.photoPath),
                look: photo.look,
                seed: StripGenerator.photoLookSeed(for: photo.lookSeedDate)
            )
        }
        do {
            let encoded = try await Task.detached(priority: .userInitiated) {
                try jobs.map { job in
                    guard let original = UIImage(contentsOfFile: job.url.path()) else {
                        throw AppError.saveToLibraryFailed
                    }
                    return try ImageProcessor.fullResolutionHEIC(of: original, look: job.look, seed: job.seed)
                }
            }.value
            try await savePhotosData(encoded)
            lastExportCount = encoded.count
        } catch let error as AppError {
            errorState?.raise(error)
        } catch {
            errorState?.raise(.saveToLibraryFailed)
        }
    }

    private struct ExportJob: Sendable {
        let url: URL
        let look: FilmLook
        let seed: UInt64
    }

    // MARK: Strips (v5 F6, OPEN: v5-8)

    /// Strip source from Roll photos, in the order given and capped at the
    /// strip size. Linked, not copied (v5-8): each item carries the photo's
    /// **current** look, read now, which As shot renders as is. Photos whose
    /// file can't be read are skipped.
    static func stripItems(from photos: [RollPhoto]) -> [StripItem] {
        photos.prefix(Constants.Roll.maxPhotosPerStrip).compactMap { photo in
            guard let image = loadPhoto(for: photo) else { return nil }
            return StripItem(image: image, caption: "", entryID: nil, look: photo.look)
        }
    }

    /// Whether a strip can still take another Roll photo.
    static func canAddToStrip(selectedCount: Int) -> Bool {
        selectedCount < Constants.Roll.maxPhotosPerStrip
    }
}
