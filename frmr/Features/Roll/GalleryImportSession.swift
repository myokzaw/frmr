import Foundation
import Observation
import Photos
import SwiftData
import UIKit

/// One gallery import from pick to last photo (F-122-E): opens the photo
/// editor on each pick in turn and keeps the `ImportBatch` in step with what
/// the editor reports. One photo is loaded at a time; the next is not read
/// until the one on screen is done.
@Observable
final class GalleryImportSession: Identifiable {
    let id = UUID()
    private(set) var batch: ImportBatch
    /// The editor on the pick being looked at; nil while the next one loads.
    private(set) var current: PhotoEditViewModel?
    /// Set after Continue to diary; the flow shows the prompt, then moves on.
    private(set) var diaryContinuation: PhotoEditViewModel.DiaryContinuation?
    /// Called once, when the batch is over, to dismiss the cover.
    @ObservationIgnored var onClose: (() -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let errorState: ErrorState
    @ObservationIgnored private let load: (Int) async throws -> UIImage
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let savePhotoData: @Sendable (Data) async throws -> Void
    @ObservationIgnored private var didClose = false

    /// - Parameter load: develops pick `index` into the working photo.
    init(
        count: Int,
        context: ModelContext,
        errorState: ErrorState,
        now: @escaping () -> Date = { .now },
        savePhotoData: (@Sendable (Data) async throws -> Void)? = nil,
        load: @escaping (Int) async throws -> UIImage
    ) {
        self.batch = ImportBatch(total: count)
        self.context = context
        self.errorState = errorState
        self.now = now
        self.load = load
        self.savePhotoData = savePhotoData ?? { try await PHPhotoLibrary.saveToCameraRoll(photoData: $0) }
    }

    func start() async {
        guard current == nil, diaryContinuation == nil else { return }
        await presentCurrent()
    }

    /// Back from the diary prompt: on to the next pick.
    func diaryFinished() {
        diaryContinuation = nil
        Task { await presentCurrent() }
    }

    /// Opens the next readable pick; an unreadable one raises its error and
    /// is passed over. Closes when none is left.
    func presentCurrent() async {
        while let index = batch.currentIndex {
            do {
                let photo = try await load(index)
                let edit = PhotoEditViewModel(
                    importing: photo, importedAt: now(), counterText: batch.counterText,
                    hasRemaining: batch.hasRemaining, savePhotoData: savePhotoData
                )
                edit.errorState = errorState
                edit.onFinish = { [weak self, weak edit] outcome in
                    guard let self, let edit else { return }
                    self.finished(outcome, of: edit)
                }
                current = edit
                return
            } catch {
                errorState.raise(Self.appError(from: error))
                batch.markFailed()
            }
        }
        close()
    }

    private func finished(_ outcome: PhotoEditViewModel.Outcome, of edit: PhotoEditViewModel) {
        current = nil
        switch outcome {
        case .saved:
            batch.markSaved()
            Task { await presentCurrent() }
        case .skipped:
            batch.markSkipped()
            Task { await presentCurrent() }
        case .continuedToDiary:
            batch.markSaved()
            guard let next = edit.diaryContinuation else {
                Task { await presentCurrent() }
                return
            }
            diaryContinuation = next
        case .appliedToRest:
            batch.markSaved()
            Task { await saveRest(with: ImportBatch.restLook(from: edit.look)) }
        case .discarded, .retaken, .deleted:
            batch.cancel()
            close()
        }
    }

    /// Apply to rest: every remaining pick goes into the Roll with `look`,
    /// then the batch finishes. Unreadable picks are passed over and raise one
    /// alert at the end, not one each.
    private func saveRest(with look: FilmLook) async {
        var lastError: AppError?
        while let index = batch.currentIndex {
            do {
                let photo = try await load(index)
                try RollViewModel.insert(
                    original: photo, look: look, capturedAt: now(), context: context, source: .imported
                )
                batch.markSaved()
            } catch {
                lastError = Self.appError(from: error)
                batch.markFailed()
            }
        }
        if let lastError { errorState.raise(lastError) }
        close()
    }

    private func close() {
        guard !didClose else { return }
        didClose = true
        current = nil
        onClose?()
    }

    private static func appError(from error: Error) -> AppError {
        if let error = error as? AppError { return error }
        return .importFailed
    }
}
