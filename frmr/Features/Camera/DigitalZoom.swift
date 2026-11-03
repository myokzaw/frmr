import CoreGraphics
import Foundation

/// The camera's digital zoom (F-122-G), pure so it is unit-testable. The
/// zoom is an app-side value: the viewfinder is scaled about its centre and
/// the saved photo gets a centred crop. The device itself stays at 1x.
nonisolated enum DigitalZoom {
    private typealias C = Constants.Camera

    /// Inside 1...`maxDigitalZoom` and on a 0.2 step. Non-finite reads as 1x.
    /// The epsilon keeps a half step rounding up (1.1 is 1.2, 2.9 is 3.0).
    static func clamped(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return C.minZoomFactor }
        let steps = ((zoom - C.minZoomFactor) / C.zoomStep + C.zoomSnapEpsilon).rounded()
        return min(max(C.minZoomFactor + steps * C.zoomStep, C.minZoomFactor), C.maxDigitalZoom)
    }

    /// Inside 1...`maxDigitalZoom` but not snapped: the live value under a
    /// pinch or a ruler drag. Non-finite reads as 1x.
    static func clampedContinuous(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return C.minZoomFactor }
        return min(max(zoom, C.minZoomFactor), C.maxDigitalZoom)
    }

    /// One smoothing step of the film preview's zoom: exponential approach
    /// to `target` over `dt` seconds. It never overshoots, and lands exactly
    /// on the target once within `zoomSettleEpsilon`.
    static func next(current: CGFloat, target: CGFloat, dt: TimeInterval) -> CGFloat {
        let gap = target - current
        guard abs(gap) > C.zoomSettleEpsilon else { return target }
        let step = min(max(dt, 0), C.zoomSmoothingMaxStep)
        let fraction = CGFloat(1 - exp(-step / C.zoomSmoothingTime))
        let moved = current + gap * fraction
        return abs(target - moved) <= C.zoomSettleEpsilon ? target : moved
    }

    /// Whether this zoom changes anything (one step above 1x counts).
    static func isZoomed(_ zoom: CGFloat) -> Bool { zoom > C.minZoomFactor + C.zoomStep / 2 }

    /// "2.4×", and "1×" at 1x.
    static func readout(_ zoom: CGFloat) -> String {
        let value = clamped(zoom)
        return isZoomed(value) ? String(format: "%.1f×", Double(value)) : "1×"
    }

    /// The number alone, for VoiceOver ("Zoom, 2.4 times").
    static func spokenValue(_ zoom: CGFloat) -> String {
        let value = clamped(zoom)
        return isZoomed(value) ? String(format: "%.1f", Double(value)) : "1"
    }

    /// The crop a shot at `zoom` is saved with: the centred rect of size
    /// 1/zoom by 1/zoom of the upright photo, Original preset, at the photo's
    /// orientation. nil at 1x. `zoom` may be the live, unsnapped value, so a
    /// shot taken mid-pinch is cut to what the viewfinder shows.
    static func cropRect(zoom: CGFloat, isLandscape: Bool) -> CropRect? {
        let value = clampedContinuous(zoom)
        guard value > C.minZoomFactor + C.zoomSnapEpsilon else { return nil }
        let side = 1 / Double(value)
        let origin = (1 - side) / 2
        return CropRect(
            rect: CGRect(x: origin, y: origin, width: side, height: side),
            preset: .original,
            isLandscape: isLandscape
        )
    }

    /// Where a point on the screen lands in the unscaled picture, which is the
    /// space `captureDevicePointConverted(fromLayerPoint:)` and the film
    /// renderer's frame mapping work in. The picture is scaled about the
    /// centre of `size`, so the visible centre is the picture's centre and a
    /// visible corner is the corner of the centred 1/zoom rect.
    static func unscaledPoint(_ point: CGPoint, zoom: CGFloat, in size: CGSize) -> CGPoint {
        let value = max(zoom, C.minZoomFactor)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: centre.x + (point.x - centre.x) / value,
            y: centre.y + (point.y - centre.y) / value
        )
    }

    /// The inverse: where a point of the unscaled picture is drawn.
    static func scaledPoint(_ point: CGPoint, zoom: CGFloat, in size: CGSize) -> CGPoint {
        let value = max(zoom, C.minZoomFactor)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: centre.x + (point.x - centre.x) * value,
            y: centre.y + (point.y - centre.y) * value
        )
    }
}
