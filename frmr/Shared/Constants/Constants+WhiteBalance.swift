import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: White balance presets (temperature K, tint)
    enum WhiteBalance {
        static let sunlight: (Float, Float) = (5500, 10)
        static let cloudy: (Float, Float) = (6500, 15)
        static let fluorescent: (Float, Float) = (4000, -20)
        static let shade: (Float, Float) = (7500, 20)
        static let tungsten: (Float, Float) = (3200, 0)
        static let manualMin: Float = 2500
        static let manualMax: Float = 8000
    }
}
