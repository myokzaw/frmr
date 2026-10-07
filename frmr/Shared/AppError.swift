import Foundation
import Observation
import SwiftUI

enum AppError: LocalizedError {
    case cameraPermissionDenied
    case photoLibraryPermissionDenied
    case captureFailed(reason: String)
    case rawProcessingFailed
    case saveToLibraryFailed
    case stripRenderFailed
    case persistenceFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to take photos. Enable it in Settings."
        case .photoLibraryPermissionDenied:
            return "Photo library access is required to save your strips. Enable it in Settings."
        case .captureFailed(let reason):
            return "Couldn't capture the photo. \(reason)"
        case .rawProcessingFailed:
            return "Couldn't process the photo. The entry was saved with the JPEG preview instead."
        case .saveToLibraryFailed:
            return "Couldn't save to your camera roll. Check your storage and permissions."
        case .stripRenderFailed:
            return "Couldn't generate the strip. Try again."
        case .persistenceFailed(let reason):
            return "Couldn't save your entry. \(reason)"
        }
    }
}

// Shared error state — injected into the environment at the app root
@Observable
final class ErrorState {
    var current: AppError?

    // Binding surface for the root alert: setting false dismisses the error
    var isPresenting: Bool {
        get { current != nil }
        set {
            if !newValue {
                current = nil
            }
        }
    }

    func raise(_ error: AppError) {
        // Always log; the alert handles user-facing display
        print("[AppError] \(error.localizedDescription)")
        current = error
    }

    func clear() {
        current = nil
    }
}

// Only the topmost presented view can show an alert, so this is attached to
// the root AND to every fullScreenCover root — errors raised inside a cover
// would otherwise stay invisible until the cover closes.
struct AppErrorAlert: ViewModifier {
    @Bindable var errorState: ErrorState

    func body(content: Content) -> some View {
        content.alert(
            "Something went wrong",
            isPresented: $errorState.isPresenting,
            presenting: errorState.current
        ) { _ in
            Button("OK", role: .cancel) { errorState.clear() }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

extension View {
    func appErrorAlert(_ errorState: ErrorState) -> some View {
        modifier(AppErrorAlert(errorState: errorState))
    }
}
