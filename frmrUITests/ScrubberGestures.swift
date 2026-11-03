import XCTest

// F-122-C follow-up: the ruler scrubbers no longer jump to a tapped spot.
// The marker stays centred and the ruler follows the finger, so dragging
// left raises the value and dragging right lowers it.
extension XCUIElement {
    /// One drag across the ruler by `points` (negative = left = higher value).
    func scrub(by points: CGFloat) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: points, dy: 0)))
    }

    /// Enough full-width swipes to reach an end of any scale; the ruler stops there.
    func scrubToEnd(increasing: Bool, swipes: Int = 5) {
        let from = coordinate(withNormalizedOffset: CGVector(dx: increasing ? 0.92 : 0.08, dy: 0.5))
        let to = coordinate(withNormalizedOffset: CGVector(dx: increasing ? 0.08 : 0.92, dy: 0.5))
        for _ in 0..<swipes {
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }
}
