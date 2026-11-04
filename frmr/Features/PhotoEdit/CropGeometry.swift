import CoreGraphics
import Foundation

/// The Crop tool's geometry (F-122-F), pure so it is unit-testable and the
/// view stays dumb. Rects are normalised (0…1 of the upright photo, origin
/// top-left); ratios are in pixels, so every function that keeps a ratio
/// needs the photo's pixel size.
nonisolated enum CropGeometry {
    enum Handle: CaseIterable, Sendable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var accessibilityLabel: String {
            switch self {
            case .topLeft: return "Top left corner"
            case .top: return "Top edge"
            case .topRight: return "Top right corner"
            case .right: return "Right edge"
            case .bottomRight: return "Bottom right corner"
            case .bottom: return "Bottom edge"
            case .bottomLeft: return "Bottom left corner"
            case .left: return "Left edge"
            }
        }
    }

    // MARK: Ratios

    /// The orientation a fixed preset starts in: that of the photo.
    static func defaultIsLandscape(for imageSize: CGSize) -> Bool { imageSize.width > imageSize.height }

    /// Width over height in pixels; nil for Free. Original is the photo's own
    /// ratio, or its inverse once the frame has been swapped to the other
    /// orientation (`isLandscape` differs from the photo's).
    static func ratio(for preset: CropPreset, isLandscape: Bool, imageSize: CGSize) -> CGFloat? {
        switch preset {
        case .free: return nil
        case .original:
            guard imageSize.width > 0, imageSize.height > 0 else { return nil }
            let own = imageSize.width / imageSize.height
            return isLandscape == defaultIsLandscape(for: imageSize) ? own : 1 / own
        default:
            guard let portrait = preset.portraitRatio else { return nil }
            return CGFloat(isLandscape ? 1 / portrait : portrait)
        }
    }

    /// The smallest crop side in pixels.
    static func minimumSide(imageSize: CGSize) -> CGFloat {
        CGFloat(Constants.Crop.minimumShortSideFraction) * min(imageSize.width, imageSize.height)
    }

    // MARK: Presets

    /// The largest rect of the preset's ratio, centred; the whole photo for
    /// Free and for Original in the photo's own orientation.
    static func fit(_ preset: CropPreset, isLandscape: Bool, in imageSize: CGSize) -> CGRect {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard imageSize.width > 0, imageSize.height > 0,
              let r = ratio(for: preset, isLandscape: isLandscape, imageSize: imageSize),
              abs(r - imageSize.width / imageSize.height) > 1e-9
        else { return whole }
        let (w, h): (CGFloat, CGFloat) = imageSize.width / imageSize.height >= r
            ? (imageSize.height * r, imageSize.height)
            : (imageSize.width, imageSize.width / r)
        return normalised(CGRect(x: (imageSize.width - w) / 2, y: (imageSize.height - h) / 2, width: w, height: h), imageSize)
    }

    /// `rect` turned to the other orientation: the same area and centre,
    /// shrunk to fit the photo. A fixed ratio and Original take the other
    /// orientation's ratio; Free swaps the frame's own width and height.
    static func swapped(_ rect: CGRect, preset: CropPreset, toLandscape: Bool, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let frameRatio = (rect.width * imageSize.width) / (rect.height * imageSize.height)
        guard let r = ratio(for: preset, isLandscape: toLandscape, imageSize: imageSize) ?? (preset == .free ? 1 / frameRatio : nil)
        else { return rect }
        let area = rect.width * imageSize.width * rect.height * imageSize.height
        var h = (area / r).squareRoot()
        var w = h * r
        let shrink = min(1, imageSize.width / w, imageSize.height / h)
        w *= shrink
        h *= shrink
        let centre = CGPoint(x: rect.midX * imageSize.width, y: rect.midY * imageSize.height)
        return normalised(inside(CGRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h), imageSize), imageSize)
    }

    // MARK: Moving and resizing

    /// `rect` moved by a normalised `delta`, kept inside the photo and
    /// snapped onto an edge it comes close to.
    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let snap = CGFloat(Constants.Crop.snapDistance)
        func place(_ origin: CGFloat, size: CGFloat) -> CGFloat {
            let limit = 1 - size
            let clamped = min(max(origin, 0), max(limit, 0))
            if clamped < snap { return 0 }
            if limit - clamped < snap { return max(limit, 0) }
            return clamped
        }
        return CGRect(
            x: place(rect.minX + delta.width, size: rect.width),
            y: place(rect.minY + delta.height, size: rect.height),
            width: rect.width, height: rect.height
        )
    }

    /// Where `handle` sits on `rect` (normalised).
    static func position(of handle: Handle, on rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// `rect` with `handle` dragged to the normalised `point`. The opposite
    /// side (corner) or edge stays put; the frame never flips, never
    /// leaves the photo and never drops below the minimum size. With a
    /// `ratio` (pixels, width over height) it is kept: a corner fits the
    /// ratio inside the dragged box; an edge resizes about the frame's centre
    /// line.
    static func resized(_ rect: CGRect, handle: Handle, to point: CGPoint, imageSize: CGSize, ratio: CGFloat?) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let width = imageSize.width, height = imageSize.height
        let m = minimumSide(imageSize: imageSize)
        let box = CGRect(x: rect.minX * width, y: rect.minY * height, width: rect.width * width, height: rect.height * height)
        let p = CGPoint(x: min(max(point.x * width, 0), width), y: min(max(point.y * height, 0), height))
        let r = ratio.flatMap { $0 > 0 ? $0 : nil }
        var result = box

        func clampSize(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(upper, lower))
        }

        switch handle {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let sx: CGFloat = (handle == .topRight || handle == .bottomRight) ? 1 : -1
            let sy: CGFloat = (handle == .bottomLeft || handle == .bottomRight) ? 1 : -1
            let anchor = CGPoint(x: sx > 0 ? box.minX : box.maxX, y: sy > 0 ? box.minY : box.maxY)
            let roomW = sx > 0 ? width - anchor.x : anchor.x
            let roomH = sy > 0 ? height - anchor.y : anchor.y
            var w = max(sx * (p.x - anchor.x), 0)
            var h = max(sy * (p.y - anchor.y), 0)
            if let r {
                w = clampSize(min(w, h * r), lower: max(m, m * r), upper: min(roomW, roomH * r))
                h = w / r
            } else {
                w = clampSize(w, lower: m, upper: roomW)
                h = clampSize(h, lower: m, upper: roomH)
            }
            result = CGRect(x: sx > 0 ? anchor.x : anchor.x - w, y: sy > 0 ? anchor.y : anchor.y - h, width: w, height: h)
        case .left, .right:
            let sx: CGFloat = handle == .right ? 1 : -1
            let anchorX = sx > 0 ? box.minX : box.maxX
            let room = sx > 0 ? width - anchorX : anchorX
            var w = max(sx * (p.x - anchorX), 0)
            if let r {
                let tallest = 2 * min(box.midY, height - box.midY)
                w = clampSize(w, lower: max(m, m * r), upper: min(room, tallest * r))
                let h = w / r
                result = CGRect(x: sx > 0 ? anchorX : anchorX - w, y: box.midY - h / 2, width: w, height: h)
            } else {
                w = clampSize(w, lower: m, upper: room)
                result = CGRect(x: sx > 0 ? anchorX : anchorX - w, y: box.minY, width: w, height: box.height)
            }
        case .top, .bottom:
            let sy: CGFloat = handle == .bottom ? 1 : -1
            let anchorY = sy > 0 ? box.minY : box.maxY
            let room = sy > 0 ? height - anchorY : anchorY
            var h = max(sy * (p.y - anchorY), 0)
            if let r {
                let widest = 2 * min(box.midX, width - box.midX)
                h = clampSize(h, lower: max(m, m / r), upper: min(room, widest / r))
                let w = h * r
                result = CGRect(x: box.midX - w / 2, y: sy > 0 ? anchorY : anchorY - h, width: w, height: h)
            } else {
                h = clampSize(h, lower: m, upper: room)
                result = CGRect(x: box.minX, y: sy > 0 ? anchorY : anchorY - h, width: box.width, height: h)
            }
        }
        return normalised(inside(result, imageSize), imageSize)
    }

    /// How many of the photo's four edges the frame lies on (for the snap
    /// haptic: it fires when this goes up).
    static func edgesTouching(_ rect: CGRect) -> Int {
        let slack = CGFloat(Constants.Crop.edgeEpsilon)
        return [rect.minX <= slack, rect.minY <= slack, rect.maxX >= 1 - slack, rect.maxY >= 1 - slack]
            .filter { $0 }.count
    }

    // MARK: Layout

    /// The photo scaled to fit `container`, centred.
    static func fittedFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    // MARK: Helpers

    /// A pixel-space rect shifted (and, if larger than the photo, shrunk) to lie inside it.
    private static func inside(_ rect: CGRect, _ size: CGSize) -> CGRect {
        let w = min(rect.width, size.width), h = min(rect.height, size.height)
        return CGRect(
            x: min(max(rect.minX, 0), size.width - w), y: min(max(rect.minY, 0), size.height - h),
            width: w, height: h
        )
    }

    private static func normalised(_ rect: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: rect.minX / size.width, y: rect.minY / size.height, width: rect.width / size.width, height: rect.height / size.height)
    }
}
