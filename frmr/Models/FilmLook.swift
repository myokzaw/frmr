import Foundation

/// One photo's complete film look (v5 F5): the stock, an optional print
/// choice, black and white, and a 0…1 strength for each physical effect.
///
/// It is the single value the Photo editor, the Roll, the strip screen,
/// the diary review and Settings all describe a look with. A strength of 1
/// is exactly the v4 strength of that effect and 0 renders pixel-identical
/// to the effect being off (`ImageProcessor` skips a zero-strength effect);
/// the slider may go to `Constants.ImageProcessing.Film.Strength.sliderMaximum`
/// (OPEN: v5-6).
///
/// nonisolated so the render pipeline and the Roll's persistence can read it
/// off the main actor.
nonisolated struct FilmLook: Hashable, Sendable, Codable {
    var stock: StripCustomization.FilmStock
    /// nil = the stock's default print (v4 F3). Named `printStock`, not
    /// `print`, so it never shadows the global `print` inside this type.
    var printStock: StripCustomization.PrintStock?
    var blackAndWhite: Bool
    var strengths: Strengths
    /// Exposure compensation in EV (v5.2 F-EXP), applied to linear light
    /// before halation and the film cube. 0 changes nothing.
    var exposure: Double

    init(
        stock: StripCustomization.FilmStock,
        printStock: StripCustomization.PrintStock? = nil,
        blackAndWhite: Bool = false,
        strengths: Strengths? = nil,
        exposure: Double = 0
    ) {
        self.exposure = FilmLook.snappedExposure(exposure)
        self.stock = stock
        self.printStock = printStock
        self.blackAndWhite = blackAndWhite
        self.strengths = strengths ?? .defaults(for: stock)
    }

    /// A stock on its default print with its default effects: the look a
    /// fresh capture starts from and "Reset to stock defaults" returns to.
    static func stockDefaults(for stock: StripCustomization.FilmStock) -> FilmLook {
        FilmLook(stock: stock)
    }

    /// The look every unedited photo has: stock Off, nothing applied.
    static let original = FilmLook(stock: .none)

    /// True while this look equals the stock's defaults (the Reset action's
    /// enabled state).
    var isStockDefault: Bool { self == .stockDefaults(for: stock) }

    /// Whether anything would change the photo: Off with no B&W is the
    /// untouched original.
    var altersPhoto: Bool { stock != .none || blackAndWhite || exposure != 0 }

    // MARK: Exposure (v5.2 F-EXP)

    /// The Exposure tool's range, in EV.
    static let exposureRange: ClosedRange<Double> = Constants.ImageProcessing.Film.Exposure.range
    /// One notch of the Exposure tool: a third of a stop.
    static let exposureStep: Double = Constants.ImageProcessing.Film.Exposure.step

    /// `value` clamped to `exposureRange` and rounded to the nearest
    /// third of a stop; NaN reads as 0. Snapping is exact: the same step
    /// always yields the same Double, so equal looks compare equal.
    static func snappedExposure(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value, exposureRange.lowerBound), exposureRange.upperBound)
        let steps = (clamped / exposureStep).rounded()
        return steps == 0 ? 0 : steps / (1 / exposureStep).rounded()
    }

    /// The linear-light gain for `exposure` EV: 2^EV.
    var exposureGain: Double { pow(2, exposure) }

    /// The slider range every strength is clamped to.
    static let strengthRange: ClosedRange<Double> = 0...Constants.ImageProcessing.Film.Strength.sliderMaximum

    // MARK: Effects

    /// The five sliders, in the order the Effects tab lists them.
    enum Effect: String, CaseIterable, Identifiable, Sendable {
        case halation
        case haze
        case lightLeak
        case grain
        case vignette

        var id: String { rawValue }

        /// Haze is the v4 bloom under its v5 name.
        var label: String {
            switch self {
            case .halation: return "Halation"
            case .haze: return "Haze"
            case .lightLeak: return "Light leak"
            case .grain: return "Grain"
            case .vignette: return "Vignette"
            }
        }

        var defaultStrength: Double {
            typealias S = Constants.ImageProcessing.Film.Strength
            switch self {
            case .halation: return S.defaultHalation
            case .haze: return S.defaultHaze
            case .lightLeak: return S.defaultLightLeak
            case .grain: return S.defaultGrain
            case .vignette: return S.defaultVignette
            }
        }
    }

    /// Strength per effect. `Codable` accepts every earlier shape: a Bool
    /// (a v4 toggle: on → the v4 strength, off → 0), a number, a missing
    /// key (the default) and the old `bloom` key (now haze).
    struct Strengths: Hashable, Sendable, Codable {
        var halation: Double
        var haze: Double
        var lightLeak: Double
        var grain: Double
        var vignette: Double

        init(
            halation: Double = Effect.halation.defaultStrength,
            haze: Double = Effect.haze.defaultStrength,
            lightLeak: Double = Effect.lightLeak.defaultStrength,
            grain: Double = Effect.grain.defaultStrength,
            vignette: Double = Effect.vignette.defaultStrength
        ) {
            self.halation = halation
            self.haze = haze
            self.lightLeak = lightLeak
            self.grain = grain
            self.vignette = vignette
        }

        /// Every stock shares one default set; the per-stock difference
        /// lives in the stock's own halation and grain constants.
        static let stockDefaults = Strengths()

        static func defaults(for stock: StripCustomization.FilmStock) -> Strengths {
            .stockDefaults
        }

        /// Every effect off, the v4 "all toggles off" look.
        static let allOff = Strengths(halation: 0, haze: 0, lightLeak: 0, grain: 0, vignette: 0)

        subscript(effect: Effect) -> Double {
            get {
                switch effect {
                case .halation: return halation
                case .haze: return haze
                case .lightLeak: return lightLeak
                case .grain: return grain
                case .vignette: return vignette
                }
            }
            set {
                switch effect {
                case .halation: halation = newValue
                case .haze: haze = newValue
                case .lightLeak: lightLeak = newValue
                case .grain: grain = newValue
                case .vignette: vignette = newValue
                }
            }
        }

        /// Every strength inside `FilmLook.strengthRange`; NaN reads as 0.
        var clamped: Strengths {
            var result = self
            for effect in Effect.allCases {
                result[effect] = FilmLook.clampedStrength(self[effect])
            }
            return result
        }

        private enum CodingKeys: String, CodingKey {
            case halation, haze, lightLeak, grain, vignette
            case bloom  // v4 name of haze, read but never written
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func strength(_ key: CodingKeys, _ effect: Effect) -> Double {
                if let number = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil {
                    return FilmLook.clampedStrength(number)
                }
                if let toggle = (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? nil {
                    return toggle ? Constants.ImageProcessing.Film.Strength.migratedOn : 0
                }
                return effect.defaultStrength
            }
            self.halation = strength(.halation, .halation)
            let hazeKey: CodingKeys = container.contains(.haze) ? .haze : .bloom
            self.haze = strength(hazeKey, .haze)
            self.lightLeak = strength(.lightLeak, .lightLeak)
            self.grain = strength(.grain, .grain)
            self.vignette = strength(.vignette, .vignette)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(halation, forKey: .halation)
            try container.encode(haze, forKey: .haze)
            try container.encode(lightLeak, forKey: .lightLeak)
            try container.encode(grain, forKey: .grain)
            try container.encode(vignette, forKey: .vignette)
        }
    }

    static func clampedStrength(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, strengthRange.lowerBound), strengthRange.upperBound)
    }

    // MARK: Stored form

    private enum CodingKeys: String, CodingKey {
        case stock, printStock, blackAndWhite, strengths, exposure
        case effects  // the v4 FilmEffects key, read but never written
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stock = try container.decodeIfPresent(StripCustomization.FilmStock.self, forKey: .stock) ?? .none
        self.stock = stock
        // An unknown print falls back to the stock's default rather than
        // making the whole look unreadable
        self.printStock = (try? container.decodeIfPresent(StripCustomization.PrintStock.self, forKey: .printStock)) ?? nil
        self.blackAndWhite = try container.decodeIfPresent(Bool.self, forKey: .blackAndWhite) ?? false
        let key: CodingKeys = container.contains(.strengths) ? .strengths : .effects
        self.strengths = try container.decodeIfPresent(Strengths.self, forKey: key) ?? .defaults(for: stock)
        // Looks stored before v5.2 have no exposure: 0 EV
        self.exposure = FilmLook.snappedExposure((try? container.decodeIfPresent(Double.self, forKey: .exposure)) ?? 0)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stock, forKey: .stock)
        try container.encodeIfPresent(printStock, forKey: .printStock)
        try container.encode(blackAndWhite, forKey: .blackAndWhite)
        try container.encode(strengths, forKey: .strengths)
        try container.encode(exposure, forKey: .exposure)
    }

    // MARK: Pipeline bridge

    /// The strip-pipeline description of this look (paper white; the strip
    /// supplies its own background).
    var customization: StripCustomization {
        var customization = StripCustomization()
        customization.filmStock = stock
        customization.printStock = printStock
        customization.strengths = strengths.clamped
        customization.blackAndWhite = blackAndWhite
        customization.exposure = exposure
        return customization
    }

    /// The print this look renders on; nil for Off.
    var resolvedPrint: StripCustomization.PrintStock? { customization.resolvedPrint }

    /// B&W on for a monochrome stock whatever the toggle says (v4 F7).
    var rendersInBlackAndWhite: Bool { customization.rendersInBlackAndWhite }

    // MARK: Editing rules (shared by the Photo editor and its tests)

    /// Switching stock keeps the user's effect strengths and drops a print
    /// the new stock can't use.
    func with(stock newStock: StripCustomization.FilmStock) -> FilmLook {
        var look = self
        look.stock = newStock
        if let printStock, !newStock.availablePrints.contains(printStock) {
            look.printStock = nil
        }
        return look
    }

    static func encoded(_ look: FilmLook) -> Data? {
        try? JSONEncoder().encode(look)
    }

    /// Decodes a stored look; unreadable data reads as the original (Off)
    /// so a damaged row still shows its photo.
    static func decoded(from data: Data) -> FilmLook {
        (try? JSONDecoder().decode(FilmLook.self, from: data)) ?? .original
    }
}
