import SwiftUI

nonisolated enum WBMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case sunlight
    case cloudy
    case shade
    case tungsten
    case fluorescent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .sunlight: return "Daylight"
        case .cloudy: return "Cloudy"
        case .shade: return "Shade"
        case .tungsten: return "Tungsten"
        case .fluorescent: return "Fluorescent"
        }
    }

    // nil means continuous auto white balance
    var temperatureAndTint: (temperature: Float, tint: Float)? {
        switch self {
        case .auto: return nil
        case .sunlight: return Constants.WhiteBalance.sunlight
        case .cloudy: return Constants.WhiteBalance.cloudy
        case .shade: return Constants.WhiteBalance.shade
        case .tungsten: return Constants.WhiteBalance.tungsten
        case .fluorescent: return Constants.WhiteBalance.fluorescent
        }
    }

    // SF Symbol per mode. Icons, not text: "Fluorescent" in a rotating chip
    // would be wider than any fixed frame can hold when turned on its side.
    var symbolName: String {
        switch self {
        case .auto: return "a.circle"
        case .sunlight: return "sun.max"
        case .cloudy: return "cloud"
        case .shade: return "cloud.sun"
        case .tungsten: return "lightbulb"
        case .fluorescent: return "light.panel"
        }
    }
}
