import CoreGraphics
import Foundation

/// The aspect choices of the Crop tool (F-122-F).
nonisolated enum CropPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case free
    case threeByFour
    case fourByFive
    case oneByOne
    case sixteenByNine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .free: return "Free"
        case .threeByFour: return "3:4"
        case .fourByFive: return "4:5"
        case .oneByOne: return "1:1"
        case .sixteenByNine: return "16:9"
        }
    }

    /// What VoiceOver says ("3 by 4").
    var spokenLabel: String { label.replacingOccurrences(of: ":", with: " by ") }

    /// Width over height of the portrait form of a fixed ratio; nil for
    /// Original (the photo's own) and Free (none).
    var portraitRatio: Double? {
        switch self {
        case .original, .free: return nil
        case .threeByFour: return 3.0 / 4.0
        case .fourByFive: return 4.0 / 5.0
        case .oneByOne: return 1
        case .sixteenByNine: return 9.0 / 16.0
        }
    }

    /// Whether the portrait/landscape swap does anything: every preset but a
    /// square. (Original on a square photo also has nothing to swap; the
    /// editor checks that, as it needs the photo's size.)
    var canSwapOrientation: Bool { self != .oneByOne }
}

/// A crop (F-122-F): a rectangle in 0…1 of the **upright** original, origin
/// top-left, plus the preset and orientation it was drawn with so the tool
/// shows them again on re-open. Stored on `FilmLook.crop`.
nonisolated struct CropRect: Hashable, Sendable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var preset: CropPreset
    /// Orientation of a fixed-ratio preset (ignored by the others)
    var isLandscape: Bool

    init(rect: CGRect, preset: CropPreset = .free, isLandscape: Bool = false) {
        self.x = Double(rect.minX)
        self.y = Double(rect.minY)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
        self.preset = preset
        self.isLandscape = isLandscape
    }

    /// This crop after the photo is turned a quarter clockwise: the same
    /// region of it, with the orientation flipped to match.
    var turnedClockwise: CropRect {
        var turned = CropRect(
            rect: CGRect(x: 1 - (y + height), y: x, width: height, height: width),
            preset: preset, isLandscape: !isLandscape
        )
        turned.snapToPhotoEdges()
        return turned
    }

    // Float error must not leave a full-frame crop a hair short of whole
    private mutating func snapToPhotoEdges() {
        let slack = Constants.Crop.edgeEpsilon
        if abs(x) <= slack { x = 0 }
        if abs(y) <= slack { y = 0 }
        if x + width >= 1 - slack { width = 1 - x }
        if y + height >= 1 - slack { height = 1 - y }
    }

    /// The whole photo with Original selected: the tool's starting state.
    static let fullFrame = CropRect(rect: CGRect(x: 0, y: 0, width: 1, height: 1), preset: .original)

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Finite, inside the photo and not empty. A stored crop that fails this
    /// reads as no crop.
    var isValid: Bool {
        let slack = Constants.Crop.edgeEpsilon
        return [x, y, width, height].allSatisfy(\.isFinite)
            && width > 0 && height > 0 && x >= -slack && y >= -slack
            && x + width <= 1 + slack && y + height <= 1 + slack
    }

    /// Covers the whole photo: rendering skips it.
    var isFullFrame: Bool {
        let slack = Constants.Crop.edgeEpsilon
        return x <= slack && y <= slack && width >= 1 - 2 * slack && height >= 1 - 2 * slack
    }

    /// The crop in whole pixels of an image of `size`, origin top-left,
    /// inside the image and at least 1×1.
    func pixelRect(in size: CGSize) -> CGRect {
        let w = max(size.width.rounded(), 1), h = max(size.height.rounded(), 1)
        let x0 = min(max((x * w).rounded(), 0), w - 1)
        let y0 = min(max((y * h).rounded(), 0), h - 1)
        let x1 = min(max(((x + width) * w).rounded(), x0 + 1), w)
        let y1 = min(max(((y + height) * h).rounded(), y0 + 1), h)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// The size to decode the whole photo at so that this crop, cut out of it,
    /// still covers `output`.
    func sourceCoveringSize(forOutput output: CGSize) -> CGSize {
        CGSize(width: output.width / max(width, .leastNonzeroMagnitude), height: output.height / max(height, .leastNonzeroMagnitude))
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height, preset, isLandscape
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.x = try container.decode(Double.self, forKey: .x)
        self.y = try container.decode(Double.self, forKey: .y)
        self.width = try container.decode(Double.self, forKey: .width)
        self.height = try container.decode(Double.self, forKey: .height)
        self.preset = (try? container.decodeIfPresent(CropPreset.self, forKey: .preset)) ?? .free
        self.isLandscape = (try? container.decodeIfPresent(Bool.self, forKey: .isLandscape)) ?? false
    }
}
