import CoreGraphics
import Foundation

/// The viewfinder grid chosen in Settings (v5.2.1 F-GRID).
nonisolated enum CameraGrid: String, CaseIterable, Identifiable, Sendable {
    case off, thirds, square, golden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .thirds: "Thirds"
        case .square: "Square"
        case .golden: "Golden"
        }
    }

    /// Where the lines fall along one axis, 0...1; the same on both axes.
    static func lineFractions(for grid: CameraGrid) -> [CGFloat] {
        switch grid {
        case .off: []
        case .thirds: [1.0 / 3.0, 2.0 / 3.0]
        case .square: [0.25, 0.5, 0.75]
        case .golden: [0.382, 0.618]
        }
    }

    /// The stored choice; a missing or unknown value reads as Off.
    static func stored(in defaults: UserDefaults) -> CameraGrid {
        defaults.string(forKey: Constants.DefaultsKeys.cameraGrid).flatMap(CameraGrid.init(rawValue:)) ?? .off
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Constants.DefaultsKeys.cameraGrid)
    }
}
