import SwiftUI

// F-GRID: composition lines inside the viewfinder frame, in both camera
// layouts and both modes; never in the editor. The lines are symmetric, so
// the overlay does not rotate with the device.
struct ViewfinderGridOverlay: View {
    let grid: CameraGrid

    private typealias UI = Constants.CameraUI

    var body: some View {
        if grid != .off {
            Canvas { context, size in
                var path = Path()
                for fraction in CameraGrid.lineFractions(for: grid) {
                    path.move(to: CGPoint(x: size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height * fraction))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                }
                context.stroke(path, with: .color(.white.opacity(UI.gridLineOpacity)), lineWidth: UI.gridLineWidth)
            }
            .shadow(color: .black.opacity(UI.gridShadowOpacity), radius: UI.gridShadowRadius)
            .allowsHitTesting(false)
            // An unlabeled element would be a blank VoiceOver stop; name the
            // grid instead, which also says which one is on
            .accessibilityElement()
            .accessibilityLabel("Grid: \(grid.label)")
            .accessibilityIdentifier("camera.grid")
        }
    }
}
