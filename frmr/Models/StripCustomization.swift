import SwiftUI

// Value type, not persisted as a SwiftData model.
// nonisolated so the render pipeline can read it off the main actor.
nonisolated struct StripCustomization: Equatable, Sendable {
    var background: StripBackground = .cream
    var filmStock: FilmStock = .none
    var blackAndWhite: Bool = false

    // v2 F5: replaces the old binary `filmGrain` toggle. `.none` is the old
    // "off" state; `.iso400` is the closest match to the old "on" state.
    enum FilmStock: String, CaseIterable, Identifiable, Codable, Sendable {
        case none
        case iso100
        case iso400
        case iso3200

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "Off"
            case .iso100: return "ISO 100"
            case .iso400: return "ISO 400"
            case .iso3200: return "ISO 3200"
            }
        }

        var profile: Constants.ImageProcessing.FilmStockProfile? {
            switch self {
            case .none: return nil
            case .iso100: return .iso100
            case .iso400: return .iso400
            case .iso3200: return .iso3200
            }
        }

        // Existing installs stored a Bool: false → .none, true → .iso400
        static func migrating(fromLegacyGrainEnabled enabled: Bool) -> FilmStock {
            enabled ? .iso400 : .none
        }
    }

    enum StripBackground: Equatable {
        case cream, black, white, custom(Color)

        var color: Color {
            switch self {
            case .cream: return .appCream
            case .black: return .appBlack
            case .white: return .white
            case .custom(let color): return color
            }
        }

        // Captions and the date stamp must stay legible on any background
        var contrastingTextColor: Color {
            switch self {
            case .black: return .appCream
            default: return .appBlack
            }
        }

        // Settings persistence: custom colors can't round-trip through
        // UserDefaults, so only the named backgrounds are storable defaults
        init(settingsName: String?) {
            switch settingsName {
            case "black": self = .black
            case "white": self = .white
            default: self = .cream
            }
        }

        var settingsName: String {
            switch self {
            case .black: return "black"
            case .white: return "white"
            default: return "cream"
            }
        }
    }
}
