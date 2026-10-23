import SwiftUI

// Value type, not persisted as a SwiftData model.
// nonisolated so the render pipeline can read it off the main actor.
nonisolated struct StripCustomization: Equatable, Sendable {
    var background: StripBackground = .white
    /// The strip-wide stock override (v4 F12). nil = "As shot": every frame
    /// renders on the stock it was taken on. Kept under its v4 name, not
    /// renamed to `stockOverride`, so the existing pickers keep binding to it.
    var filmStock: FilmStock? = nil
    /// nil = the stock's default print (v4 F3). A choice that the current
    /// stock cannot use (any print on slide film) also falls back to it.
    /// Only meaningful with an override; as-shot frames use their own
    /// stock's default print.
    var printStock: PrintStock? = nil
    /// Effect strengths (v5 F5), 0 = off and 1 = the v4 strength. As shot
    /// frames take these strip-level strengths too, except Roll frames,
    /// which keep their own look (`effective(forFrameStock:look:)`).
    var strengths: FilmLook.Strengths = .stockDefaults
    var blackAndWhite: Bool = false
    /// Exposure compensation in EV (v5.2 F-EXP). Per photo only: it comes
    /// from a Roll photo's `FilmLook`, never from the strip-wide settings.
    var exposure: Double = 0
    /// The linear-light gain 2^EV.
    var exposureGain: Double { exposure == 0 ? 1 : pow(2, exposure) }

    /// The v4 on/off view of the first three strengths, kept so code and
    /// tests written against the toggles still compile and mean the same
    /// thing: on is any strength above 0, switching on restores the v4
    /// strength, switching off sets 0. New code binds `strengths`.
    var effects: FilmEffects {
        get { FilmEffects(strengths: strengths) }
        set {
            strengths.halation = newValue.strengths.halation
            strengths.haze = newValue.strengths.haze
            strengths.lightLeak = newValue.strengths.lightLeak
        }
    }

    /// The print the strip is actually rendered on; nil for stock Off and
    /// for As shot (each frame then resolves its own, see `effective`).
    var resolvedPrint: PrintStock? {
        guard let filmStock, let stockDefault = filmStock.defaultPrint else { return nil }
        guard let printStock, filmStock.availablePrints.contains(printStock) else { return stockDefault }
        return printStock
    }

    /// B&W is on for a monochrome stock whatever the toggle says (v4 F7).
    var rendersInBlackAndWhite: Bool {
        blackAndWhite || (filmStock?.isMonochrome ?? false)
    }

    /// The customization one frame is rendered with (v4 F12): unchanged
    /// under an override; under As shot, the frame's own stock on that
    /// stock's default print. Effects and B&W stay strip-level either way.
    func effective(forFrameStock frameStock: FilmStock) -> StripCustomization {
        guard filmStock == nil else { return self }
        var frame = self
        frame.filmStock = frameStock
        frame.printStock = nil
        return frame
    }

    /// The customization one frame is rendered with when it may carry its
    /// own Roll look (v5 F6): under As shot such a frame renders exactly
    /// that look; an override stock, or a frame with no look, behaves as
    /// `effective(forFrameStock:)`.
    func effective(forFrameStock frameStock: FilmStock, look: FilmLook?) -> StripCustomization {
        guard filmStock == nil, let look else { return effective(forFrameStock: frameStock) }
        var frame = look.customization
        frame.background = background
        return frame
    }

    /// One photo's own look (v4 F10/F11/F13): its stock on the stock's
    /// default print with the stock's default effects, colour unless the
    /// stock is monochrome. The review screen, entry display and Download
    /// all render through this, so they agree with each other.
    static func stockDefaults(for stock: FilmStock) -> StripCustomization {
        var customization = StripCustomization()
        customization.filmStock = stock
        customization.strengths = .defaults(for: stock)
        return customization
    }

    /// The strip and Settings stock pickers' rows: As shot (nil), then
    /// every stock.
    static let stockChoices: [FilmStock?] = [nil] + FilmStock.allCases.map { $0 }

    static let asShotLabel = "As shot"

    static func label(forStockChoice choice: FilmStock?) -> String {
        choice?.label ?? asShotLabel
    }

    /// The Settings default as stored in UserDefaults: As shot is a
    /// sentinel, any stock its raw value.
    static func storedValue(forStockChoice choice: FilmStock?) -> String {
        choice?.rawValue ?? Constants.Strip.asShotStoredValue
    }

    /// Reads a stored Settings stock default. The sentinel and a missing
    /// value mean As shot; anything else is an override, migrated like
    /// every stored stock (v2 ISO values, unknown → Off).
    static func stockChoice(fromStoredValue stored: String?) -> FilmStock? {
        guard let stored, stored != Constants.Strip.asShotStoredValue else { return nil }
        return FilmStock.migrating(fromStoredValue: stored)
    }

    // v4 F3 launch set (OPEN: v4-1 — six stocks; curves in
    // Constants.ImageProcessing.Film). frmr's own names, never a brand.
    // v2's ISO cases are gone; their stored raw values migrate through
    // `migrating(fromStoredValue:)`.
    enum FilmStock: String, CaseIterable, Identifiable, Codable, Sendable {
        case none
        case daylight200
        case portrait400
        case cine500T
        case slide100
        case mono400
        case mono3200

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Off"
            case .daylight200: return "Daylight 200"
            case .portrait400: return "Portrait 400"
            case .cine500T: return "Cine 500T"
            case .slide100: return "Slide 100"
            case .mono400: return "Mono 400"
            case .mono3200: return "Mono 3200"
            }
        }

        /// The camera Film chip's code (v4 F9): short enough for a 44pt
        /// circle that rotates in place.
        var shortCode: String {
            switch self {
            case .none: return "OFF"
            case .daylight200: return "D200"
            case .portrait400: return "P400"
            case .cine500T: return "C500"
            case .slide100: return "S100"
            case .mono400: return "M400"
            case .mono3200: return "M3.2K"
            }
        }

        /// Box speed, for grain sizing; nil for Off.
        var iso: Int? {
            switch self {
            case .none: return nil
            case .daylight200: return 200
            case .portrait400, .mono400: return 400
            case .cine500T: return 500
            case .slide100: return 100
            case .mono3200: return 3200
            }
        }

        var isMonochrome: Bool { negative?.isMonochrome ?? false }

        /// Halation strength when the Halation effect is on (v4 F4); 0 for Off.
        var halationStrength: Double {
            typealias H = Constants.ImageProcessing.Film.HalationStrength
            switch self {
            case .none: return 0
            case .daylight200: return H.daylight200
            case .portrait400: return H.portrait400
            case .cine500T: return H.cine500T
            case .slide100: return H.slide100
            case .mono400: return H.mono400
            case .mono3200: return H.mono3200
            }
        }

        /// Reversal film is viewed directly, so it has no print choice.
        var isSlide: Bool { self == .slide100 }

        /// The negative's curves (v4 F2); nil for Off, the untouched fast path.
        var negative: NegativeProfile? {
            typealias N = Constants.ImageProcessing.Film.Negative
            switch self {
            case .none: return nil
            case .daylight200: return N.daylight200
            case .portrait400: return N.portrait400
            case .cine500T: return N.cine500T
            case .slide100: return N.slide100
            case .mono400: return N.mono400
            case .mono3200: return N.mono3200
            }
        }

        /// The print this stock is printed on unless the user picks another (v4 F3).
        var defaultPrint: PrintStock? {
            switch self {
            case .none: return nil
            case .daylight200, .portrait400, .mono400, .mono3200: return .lab
            case .cine500T: return .cinema
            case .slide100: return .projection
            }
        }

        /// Prints this stock can be rendered on. Projection is slide-only,
        /// and slide film is projection-only.
        var availablePrints: [PrintStock] {
            switch self {
            case .none: return []
            case .slide100: return [.projection]
            default: return PrintStock.allCases.filter { $0 != .projection }
            }
        }

        /// Whether a print picker has anything to choose between. False for
        /// Off (no prints) and slide film (projection only).
        var hasPrintChoice: Bool { availablePrints.count > 1 }

        /// Halation, bloom and light leak only mean something with a stock on.
        var hasEffects: Bool { self != .none }

        /// Grain v2 (F5) amplitude for this stock's speed; 0 for Off.
        var grainIntensity: Double {
            iso.map(FilmGrain.intensity(forISO:)) ?? 0
        }

        /// How this stock's grain is structured (v4 F14).
        var grainProfile: GrainProfile {
            switch self {
            case .mono3200: return Constants.ImageProcessing.Film.Grain.mono3200
            default: return Constants.ImageProcessing.Film.Grain.standard
            }
        }

        /// Grain v2 (F5) fine-octave size in output pixels; 0 for Off.
        var grainSizePixels: Double {
            iso.map(FilmGrain.sizePixels(forISO:)) ?? 0
        }

        // OPEN: v4-6 — legacy mapping per spec §F7, values in
        // Constants.ImageProcessing.Film.legacyStockMapping: iso100 → Daylight
        // 200, iso400 → Portrait 400, iso3200 → Cine 500T, unknown → Off.
        static func migrating(fromStoredValue stored: String?) -> FilmStock {
            guard let stored else { return .none }
            if let stock = FilmStock(rawValue: stored) {
                return stock
            }
            return Constants.ImageProcessing.Film.legacyStockMapping[stored]
                .flatMap(FilmStock.init(rawValue:)) ?? .none
        }

        // Installs older than v2 stored a Bool: false → Off, true → what v2
        // called ISO 400, which v4 maps to Portrait 400
        static func migrating(fromLegacyGrainEnabled enabled: Bool) -> FilmStock {
            enabled ? migrating(fromStoredValue: Constants.ImageProcessing.Film.legacyGrainEnabledStock) : .none
        }

        // Anything that decodes a stored stock gets the same migration
        init(from decoder: any Decoder) throws {
            let stored = try decoder.singleValueContainer().decode(String.self)
            self = FilmStock.migrating(fromStoredValue: stored)
        }
    }

    // v4 F3: what the negative is printed on.
    enum PrintStock: String, CaseIterable, Identifiable, Codable, Sendable {
        case lab
        case cinema
        case matte
        case projection

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lab: return "Lab print"
            case .cinema: return "Cinema print"
            case .matte: return "Matte paper"
            case .projection: return "Projection"
            }
        }

        var profile: PrintProfile {
            typealias P = Constants.ImageProcessing.Film.Print
            switch self {
            case .lab: return P.lab
            case .cinema: return P.cinema
            case .matte: return P.matte
            case .projection: return P.projection
            }
        }
    }

    // v4 F7's on/off effects, now a facade over `FilmLook.Strengths` (v5 F5,
    // which overturns OPEN: v4-2, Constants.ImageProcessing.Film
    // .effectsAreToggles). Source compatibility only: `bloom` is haze, and a
    // toggle is "strength above 0".
    struct FilmEffects: Equatable, Sendable {
        fileprivate(set) var strengths: FilmLook.Strengths

        fileprivate init(strengths: FilmLook.Strengths) {
            self.strengths = strengths
        }

        init(halation: Bool, bloom: Bool, lightLeak: Bool) {
            strengths = .stockDefaults
            self.halation = halation
            self.bloom = bloom
            self.lightLeak = lightLeak
        }

        var halation: Bool {
            get { strengths.halation > 0 }
            set { strengths.halation = Self.toggled(newValue, from: strengths.halation) }
        }

        var bloom: Bool {
            get { strengths.haze > 0 }
            set { strengths.haze = Self.toggled(newValue, from: strengths.haze) }
        }

        var lightLeak: Bool {
            get { strengths.lightLeak > 0 }
            set { strengths.lightLeak = Self.toggled(newValue, from: strengths.lightLeak) }
        }

        // Switching on keeps a strength the user already set
        private static func toggled(_ on: Bool, from current: Double) -> Double {
            guard on else { return 0 }
            return current > 0 ? current : Constants.ImageProcessing.Film.Strength.migratedOn
        }

        // Halation on, haze and light leak off (v4 F4–F6 defaults)
        static let stockDefaults = FilmEffects(strengths: .stockDefaults)

        /// The defaults a stock starts with. Every stock shares one set; the
        /// strength difference lives in the stock's constants.
        static func defaults(for stock: FilmStock) -> FilmEffects {
            FilmEffects(strengths: .defaults(for: stock))
        }
    }

    // v4 F8: white or black only. The stored v1–v4 default "cream" and any
    // unknown value read as white.
    /// Declaration order is the pickers' display order.
    enum StripBackground: Equatable, CaseIterable {
        case white, black

        var label: String {
            switch self {
            case .white: return "White"
            case .black: return "Black"
            }
        }

        /// The paper tone (v4 F15): warm off-white or near-black.
        var color: Color {
            let paper = paperRGB
            return Color(.sRGB, red: paper.r, green: paper.g, blue: paper.b)
        }

        var paperRGB: (r: Double, g: Double, b: Double) {
            switch self {
            case .white: return Constants.Strip.paperWhite
            case .black: return Constants.Strip.paperBlack
            }
        }

        // Captions and the date stamp must stay legible on either background
        var contrastingTextColor: Color {
            switch self {
            case .white: return .appBlack
            case .black: return .appCream
            }
        }

        init(settingsName: String?) {
            switch settingsName {
            case "black": self = .black
            default: self = .white
            }
        }

        var settingsName: String {
            switch self {
            case .white: return "white"
            case .black: return "black"
            }
        }
    }
}
