import Foundation
import UIKit

/// The after-the-shutter plumbing the diary review (v4 F10) and the Photo
/// editor (v5 F4) share: swapping the JPEG preview for the developed RAW,
/// and rendering the chosen `FilmLook` at screen size where the **last
/// request wins**. Extracted so the two view models can't drift apart.
///
/// It holds no photo and no look: the owner passes both with every
/// request and keeps its own observable state, which this reports back
/// through closures.
final class FilmLookRenderScheduler {
    private var development: Task<UIImage, Never>?
    private var developmentWatch: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var generation = 0

    // MARK: Development (JPEG preview → RAW)

    /// Starts watching a RAW development. `onDeveloped` runs on the main
    /// actor with the developed photo unless `cancel()` came first. A nil
    /// development means the preview is already final.
    func watch(development: Task<UIImage, Never>?, onDeveloped: @escaping @MainActor (UIImage) -> Void) {
        self.development = development
        guard let development else { return }
        developmentWatch = Task {
            let developed = await development.value
            guard !Task.isCancelled else { return }
            onDeveloped(developed)
        }
    }

    /// The final original: the developed RAW once it is ready, else `fallback`
    /// (the preview, when there is no RAW).
    func developedPhoto(fallback: UIImage) async -> UIImage {
        guard let development else { return fallback }
        return await development.value
    }

    // MARK: Rendering

    enum Outcome {
        case rendered(UIImage)
        case failed
    }

    /// Renders `photo` in `look` covering `pixelSize` and reports the result
    /// of the newest request only: every call cancels the previous task and
    /// bumps the generation, so a superseded render can never publish.
    ///
    /// - Parameter debounce: pause before rendering, so a burst of slider
    ///   moves renders once; nil renders at once (first display, RAW swap).
    /// - Returns: false when the look changes nothing: the original needs
    ///   no render, so `completion` has already been called with it.
    @discardableResult
    func schedule(
        photo: UIImage,
        look: FilmLook,
        seed: UInt64,
        pixelSize: CGSize,
        debounce: TimeInterval?,
        completion: @escaping @MainActor (Outcome) -> Void
    ) -> Bool {
        renderTask?.cancel()
        generation += 1
        let generation = generation

        guard look.altersPhoto else {
            renderTask = nil
            completion(.rendered(photo))
            return false
        }

        renderTask = Task { [weak self] in
            if let debounce {
                try? await Task.sleep(for: .seconds(debounce))
                guard !Task.isCancelled else { return }
            }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try ImageProcessor.renderFullLook(of: photo, look: look, seed: seed, coveringPixelSize: pixelSize) }
            }.value
            guard let self, generation == self.generation else { return }
            self.renderTask = nil
            switch result {
            case .success(let image): completion(.rendered(image))
            case .failure: completion(.failed)
            }
        }
        return true
    }

    /// Drops any pending render without publishing (the look turned
    /// into a no-op, or the screen is closing).
    func cancelRender() {
        renderTask?.cancel()
        renderTask = nil
        generation += 1
    }

    /// Waits for the newest scheduled render, for callers (and tests) that
    /// need the settled result.
    func settled() async {
        while let task = renderTask {
            await task.value
            // Superseded tasks hand over to their successor; a finished
            // newest task clears itself
            if renderTask == task { return }
        }
    }

    /// Stops updating: no more render results and no RAW swap. A Download
    /// already in flight is the caller's own task and still finishes.
    func cancel() {
        developmentWatch?.cancel()
        cancelRender()
    }
}

nonisolated extension ImageProcessor {
    /// The full-resolution HEIC both Downloads and Roll exports save
    /// (v4 F13, v5 F4/F6): `look` at the developed photo's own size, with
    /// its orientation tag. A look that changes nothing encodes the
    /// original.
    static func fullResolutionHEIC(of photo: UIImage, look: FilmLook, seed: UInt64) throws -> Data {
        try heicData(from: renderFullLook(of: photo, look: look, seed: seed))
    }
}
