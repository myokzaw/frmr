import Foundation
import Observation
import Photos
import SwiftData
import UIKit

// One source photo bound for a strip, with the diary entry it came from
// (nil for photobooth shots, which have no entries or captions)
struct StripItem {
    let image: UIImage?
    let caption: String
    let entryID: UUID?

    static let empty = StripItem(image: nil, caption: "", entryID: nil)
}

@Observable
final class StripViewModel {
    var errorState: ErrorState?

    private let items: [StripItem]
    private let isPhotobooth: Bool
    private let date: Date

    var customization: StripCustomization
    private(set) var stripImages: [UIImage] = []
    private(set) var isRendering = false

    init(items: [StripItem], isPhotobooth: Bool, date: Date = .now) {
        self.items = items
        self.isPhotobooth = isPhotobooth
        self.date = date
        self.customization = Self.defaultCustomization()
    }

    var areActionsDisabled: Bool { isRendering || stripImages.isEmpty }

    func renderStrips() async {
        isRendering = true
        defer { isRendering = false }
        Haptics.prepareStripComplete()

        let cells = items.map { StripGenerator.Cell(image: $0.image, caption: $0.caption) }
        let chunks = StripGenerator.chunked(cells, paddingWith: .empty)
        let customization = customization
        let date = date

        stripImages = await Task.detached(priority: .userInitiated) {
            chunks.map { StripGenerator.render(strip: $0, customization: customization, date: date) }
        }.value

        if !stripImages.isEmpty {
            Haptics.stripCompleted()
        }
    }

    func saveToCameraRoll() async {
        do {
            try await PHPhotoLibrary.saveToCameraRoll(stripImages)
        } catch let error as AppError {
            errorState?.raise(error)
        } catch {
            errorState?.raise(.saveToLibraryFailed)
        }
    }

    // Writes each rendered strip PNG to Documents and records a DailyStrip,
    // making it appear in the Library. Returns true on success.
    @discardableResult
    func persist(context: ModelContext) -> Bool {
        let idChunks = StripGenerator.chunked(items, paddingWith: .empty)
            .map { chunk in chunk.compactMap(\.entryID) }
        do {
            _ = try FileManager.createStripsDirectory()
            for (index, image) in stripImages.enumerated() {
                let entryIDs = index < idChunks.count ? idChunks[index] : []
                let strip = DailyStrip(createdAt: date, entryIDs: entryIDs, isPhotobooth: isPhotobooth)
                guard let data = image.pngData() else {
                    throw AppError.stripRenderFailed
                }
                try data.write(to: FileManager.documentsURL(forRelativePath: strip.imageRelativePath))
                context.insert(strip)
            }
            try context.save()
            return true
        } catch let error as AppError {
            errorState?.raise(error)
            return false
        } catch {
            errorState?.raise(.persistenceFailed(reason: error.localizedDescription))
            return false
        }
    }

    private static func defaultCustomization() -> StripCustomization {
        let defaults = UserDefaults.standard
        var customization = StripCustomization()
        customization.background = StripCustomization.StripBackground(
            settingsName: defaults.string(forKey: Constants.DefaultsKeys.stripBackground)
        )
        customization.filmStock = Self.defaultFilmStock(defaults)
        customization.blackAndWhite = defaults.bool(forKey: Constants.DefaultsKeys.stripBlackAndWhite)
        return customization
    }

    // v2 F5 replaced the grain Bool with a film stock. Installs that predate the
    // picker still only have the old key, so fall back to it once.
    private static func defaultFilmStock(_ defaults: UserDefaults) -> StripCustomization.FilmStock {
        if let stored = defaults.string(forKey: Constants.DefaultsKeys.stripFilmStock),
           let stock = StripCustomization.FilmStock(rawValue: stored) {
            return stock
        }
        return .migrating(fromLegacyGrainEnabled: defaults.bool(forKey: Constants.DefaultsKeys.stripFilmGrain))
    }
}
