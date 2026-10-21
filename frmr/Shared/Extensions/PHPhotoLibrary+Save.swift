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

    /// Saves already-encoded photo data (the v4 F13 HEIC) as one asset, so
    /// the file's own encoding and orientation tag reach the library as-is.
    static func saveToCameraRoll(photoData: Data) async throws {
        let status = await requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryPermissionDenied
        }
        do {
            try await shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: photoData, options: nil)
            }
        } catch {
            print("[PHPhotoLibrary] Camera roll save failed: \(error)")
            throw AppError.saveToLibraryFailed
        }
    }

    /// Several encoded photos as one library change (v5 F6 Roll export), so
    /// a multi-select export is one permission check and one all-or-nothing
    /// write.
    static func saveToCameraRoll(photosData: [Data]) async throws {
        guard !photosData.isEmpty else { return }
        let status = await requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw AppError.photoLibraryPermissionDenied
        }
        do {
            try await shared().performChanges {
                for data in photosData {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            }
        } catch {
            print("[PHPhotoLibrary] Camera roll save failed: \(error)")
            throw AppError.saveToLibraryFailed
        }
    }
}
