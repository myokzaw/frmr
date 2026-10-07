import Photos
import UIKit

// Shared camera-roll saving used by the strip screen and the library.
// Throws AppError so callers can surface it through ErrorState.
nonisolated extension PHPhotoLibrary {
    static func saveToCameraRoll(_ images: [UIImage]) async throws {
        let status = await requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryPermissionDenied
        }
        do {
            try await shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
        } catch {
            print("[PHPhotoLibrary] Camera roll save failed: \(error)")
            throw AppError.saveToLibraryFailed
        }
    }
}
