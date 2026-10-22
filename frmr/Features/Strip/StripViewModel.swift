import Foundation
import Observation
import Photos
import SwiftData
import UIKit

// One source photo bound for a strip, with the diary entry it came from
// (nil for photobooth shots, which have no entries or captions) and the
// stock it was taken on (v4 F11), which As shot renders it with
struct StripItem {
    let image: UIImage?
    let caption: String
    let entryID: UUID?
    let filmStock: StripCustomization.FilmStock
    /// A Roll photo's own look (v5 F6). Under As shot the frame renders
    /// exactly this look; nil for diary entries and photobooth shots, which
    /// carry only their stock.
    let look: FilmLook?

    init(
        image: UIImage?,
        caption: String,
        entryID: UUID?,
        filmStock: StripCustomization.FilmStock = .none,
        look: FilmLook? = nil
    ) {
        self.image = image
        self.caption = caption
        self.entryID = entryID
        self.filmStock = look?.stock ?? filmStock
        self.look = look
    }

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

    // MARK: Controls card state (v4 F7) — the view binds to these rather
    // than deciding visibility itself

    /// Prints the picker offers for the override stock; none for As shot,
    /// whose frames each use their own stock's default print (v4 F12).
    var availablePrints: [StripCustomization.PrintStock] {
        customization.filmStock?.availablePrints ?? []
    }

    /// Shown only for an override stock with a print choice: hidden for As
    /// shot, Off and slide film (projection only).
    var isPrintPickerVisible: Bool { customization.filmStock?.hasPrintChoice ?? false }

    /// The print picker's selection: always one of `availablePrints` while
    /// the picker is visible. Setting it records an explicit choice.
    var selectedPrint: StripCustomization.PrintStock {
        get { customization.resolvedPrint ?? .lab }
        set { customization.printStock = newValue }
    }

    var areEffectsVisible: Bool {
        Self.areEffectsVisible(override: customization.filmStock, frameStocks: items.map(\.filmStock))
    }

    /// Effects are strip-level, so they show while any frame would render
    /// them: hidden only when every effective stock is Off (v4 F12).
    nonisolated static func areEffectsVisible(
        override: StripCustomization.FilmStock?,
        frameStocks: [StripCustomization.FilmStock]
    ) -> Bool {
        if let override { return override.hasEffects }
        return frameStocks.contains(where: \.hasEffects)
    }

    /// A monochrome override is always B&W: the toggle shows on and is
    /// disabled. Under As shot, mono frames render B&W on their own and the
    /// toggle still applies to the colour frames, so it stays enabled.
    var isBlackAndWhiteLocked: Bool { customization.filmStock?.isMonochrome ?? false }

    /// The B&W toggle's binding: reads on while locked, ignores writes then.
    var blackAndWhiteToggle: Bool {
        get { customization.rendersInBlackAndWhite }
        set {
            guard !isBlackAndWhiteLocked else { return }
            customization.blackAndWhite = newValue
        }
    }

    // Every toggle in the strip screen starts a render. Without cancelling
    // the previous one they queued up and the strip lagged several taps
    // behind (v4 F1). The generation counter decides which call owns
    // `isRendering` and the result: only the newest.
    private var renderTask: Task<[UIImage]?, Never>?
    private var renderGeneration = 0

    // Dragging an effect slider re-renders many times; only the screen's
    // first completed render earns the haptic
    private(set) var hasPlayedCompletionHaptic = false

    static func shouldPlayCompletionHaptic(alreadyPlayed: Bool, hasImages: Bool) -> Bool {
        hasImages && !alreadyPlayed
    }

    func renderStrips() async {
        renderTask?.cancel()
        renderGeneration += 1
        let generation = renderGeneration
        isRendering = true
        Haptics.prepareStripComplete()

        let cells = items.map { StripGenerator.Cell(image: $0.image, caption: $0.caption, filmStock: $0.filmStock, look: $0.look) }
        let chunks = StripGenerator.chunked(cells, paddingWith: .empty)
        let customization = customization
        let date = date

        let task = Task.detached(priority: .userInitiated) { () -> [UIImage]? in
            var images: [UIImage] = []
            for (stripIndex, chunk) in chunks.enumerated() {
                if Task.isCancelled { return nil }
                images.append(StripGenerator.render(
                    strip: chunk, customization: customization, date: date, stripIndex: stripIndex
                ))
            }
            return Task.isCancelled ? nil : images
        }
        renderTask = task
        let rendered = await task.value

        // A newer call superseded this one; it keeps the spinner and the result
        guard generation == renderGeneration else { return }
        renderTask = nil
        isRendering = false
        guard let rendered else { return }
        // The previous strip stays on screen until this one is ready (no blanking)
        stripImages = rendered

        if Self.shouldPlayCompletionHaptic(alreadyPlayed: hasPlayedCompletionHaptic, hasImages: !stripImages.isEmpty) {
            hasPlayedCompletionHaptic = true
            Haptics.play(.saved)
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
        loadDefaults(from: .standard)
    }

    // MARK: Strip defaults (Settings → Strip defaults)

    /// The strip look Settings has chosen as the default, migrating values
    /// stored by older versions. Pure over the given store so tests can use
    /// a scratch suite.
    nonisolated static func loadDefaults(from defaults: UserDefaults) -> StripCustomization {
        typealias K = Constants.DefaultsKeys
        var customization = StripCustomization()
        customization.background = StripCustomization.StripBackground(
            settingsName: defaults.string(forKey: K.stripBackground)
        )
        customization.filmStock = defaultFilmStock(defaults)
        customization.printStock = defaults.string(forKey: K.stripPrintStock)
            .flatMap(StripCustomization.PrintStock.init(rawValue:))
        customization.strengths = storedStrengths(in: defaults)
        customization.blackAndWhite = defaults.bool(forKey: K.stripBlackAndWhite)
        return customization
    }

    /// Stores `customization` as the strip defaults. A nil print removes the
    /// key, so the stock's own default print applies.
    nonisolated static func storeDefaults(_ customization: StripCustomization, in defaults: UserDefaults) {
        typealias K = Constants.DefaultsKeys
        defaults.set(customization.background.settingsName, forKey: K.stripBackground)
        defaults.set(StripCustomization.storedValue(forStockChoice: customization.filmStock), forKey: K.stripFilmStock)
        if let print = customization.printStock {
            defaults.set(print.rawValue, forKey: K.stripPrintStock)
        } else {
            defaults.removeObject(forKey: K.stripPrintStock)
        }
        defaults.set(customization.strengths.halation, forKey: K.stripHalation)
        defaults.set(customization.strengths.haze, forKey: K.stripHaze)
        defaults.set(customization.strengths.lightLeak, forKey: K.stripLightLeak)
        defaults.set(customization.strengths.grain, forKey: K.stripGrain)
        defaults.set(customization.strengths.vignette, forKey: K.stripVignette)
        defaults.set(customization.blackAndWhite, forKey: K.stripBlackAndWhite)
    }

    /// The stored effect strengths (v5 F5). A key written by v4 holds a
    /// Bool: on reads as the v4 strength (1), off as 0 — which a numeric
    /// read of the same NSNumber already gives. A missing key is the
    /// default (halation on, the rest per `FilmLook.Effect.defaultStrength`).
    /// Haze falls back to the old bloom key once. `object(forKey:)` rather
    /// than `double(forKey:)`, so "never stored" stays distinguishable
    /// from 0.
    nonisolated static func storedStrengths(in defaults: UserDefaults) -> FilmLook.Strengths {
        typealias K = Constants.DefaultsKeys
        func strength(_ key: String, _ effect: FilmLook.Effect, legacyKey: String? = nil) -> Double {
            let stored = defaults.object(forKey: key) ?? legacyKey.flatMap(defaults.object(forKey:))
            guard let number = stored as? NSNumber else { return effect.defaultStrength }
            return FilmLook.clampedStrength(number.doubleValue)
        }
        return FilmLook.Strengths(
            halation: strength(K.stripHalation, .halation),
            haze: strength(K.stripHaze, .haze, legacyKey: K.stripBloom),
            lightLeak: strength(K.stripLightLeak, .lightLeak),
            grain: strength(K.stripGrain, .grain),
            vignette: strength(K.stripVignette, .vignette)
        )
    }

    /// Rewrites a v2 stock value (or the pre-v2 grain Bool) and a pre-F8
    /// background ("cream") in place, so Settings' pickers, which bind to
    /// the raw stored strings, show the migrated value instead of no
    /// selection. Idempotent; run at launch. A fresh install stores nothing,
    /// so its stock default stays As shot.
    nonisolated static func migrateLegacyDefaults(_ defaults: UserDefaults) {
        typealias K = Constants.DefaultsKeys
        let stored = defaults.string(forKey: K.stripFilmStock)
        let hasLegacyGrain = defaults.object(forKey: K.stripFilmGrain) != nil
        if stored != nil || hasLegacyGrain {
            let migrated = StripCustomization.storedValue(forStockChoice: defaultFilmStock(defaults))
            if stored != migrated {
                defaults.set(migrated, forKey: K.stripFilmStock)
            }
        }

        if let background = defaults.string(forKey: K.stripBackground) {
            let migrated = StripCustomization.StripBackground(settingsName: background).settingsName
            if background != migrated {
                defaults.set(migrated, forKey: K.stripBackground)
            }
        }
    }

    // v4 F12: no stored stock means As shot (the new default). A value
    // stored by v4 stays an override. v2 F5 replaced the grain Bool with a
    // film stock and v4 replaced the ISO stocks; installs that predate the
    // picker only have the old grain key, so fall back to it once.
    nonisolated private static func defaultFilmStock(_ defaults: UserDefaults) -> StripCustomization.FilmStock? {
        typealias K = Constants.DefaultsKeys
        if let stored = defaults.string(forKey: K.stripFilmStock) {
            return StripCustomization.stockChoice(fromStoredValue: stored)
        }
        guard defaults.object(forKey: K.stripFilmGrain) != nil else { return nil }
        return .migrating(fromLegacyGrainEnabled: defaults.bool(forKey: K.stripFilmGrain))
    }
}
