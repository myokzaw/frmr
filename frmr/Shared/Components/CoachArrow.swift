import SwiftUI

// A short curved arrow from the coach bubble down to its tab icon (v3 F5).
// Pure Path — no images, no SF Symbols. Drawn top-to-bottom in its rect:
// a gentle curve bowing toward the leading side, ending in a small head.
nonisolated struct CoachArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let start = CGPoint(x: rect.midX, y: rect.minY)
        let end = CGPoint(x: rect.midX, y: rect.maxY)
        // Control point off to the side gives the arrow its hand-drawn bow
        let control = CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        // Arrowhead: two short strokes back up from the tip
        let headLength = rect.height * 0.2
        path.move(to: CGPoint(x: end.x - headLength * 0.7, y: end.y - headLength))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x + headLength * 0.7, y: end.y - headLength * 0.6))

        return path
    }
}

#Preview {
    ZStack {
        Color.black
        CoachArrow()
            .stroke(.white, style: StrokeStyle(
                lineWidth: Constants.Onboarding.arrowStroke,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: Constants.Onboarding.arrowLength, height: Constants.Onboarding.arrowLength)
    }
}
