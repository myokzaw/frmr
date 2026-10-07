import SwiftUI

// Animated film grain over the live viewfinder (v2 F6). A static grain texture
// immediately reads as a digital filter — real grain moves between frames, so
// the noise tile is regenerated on a TimelineView cadence.
//
// Luminosity blend mode is deliberate: grain perturbs brightness only. Any
// other mode desaturates the preview.
struct GrainOverlayView: View {
    var body: some View {
        if Constants.Camera.animatedGrainEnabled {
            TimelineView(.animation(minimumInterval: Constants.Camera.grainRefreshInterval)) { timeline in
                GrainTile(phase: Self.phase(for: timeline.date))
            }
            .blendMode(.luminosity)
            .opacity(Constants.Camera.liveGrainOpacity)
            .allowsHitTesting(false)
        }
    }

    // Advances the noise tile's offset once per refresh interval, so each drawn
    // frame gets a visibly different slice of the tile.
    private static func phase(for date: Date) -> CGFloat {
        let tick = (date.timeIntervalSinceReferenceDate / Constants.Camera.grainRefreshInterval)
            .rounded(.down)
        return CGFloat(tick.truncatingRemainder(dividingBy: Constants.Camera.liveGrainTileSize))
    }
}

private struct GrainTile: View {
    let phase: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard let tile = ImageProcessor.makeLiveGrainTile(size: size, phase: phase) else {
                return
            }
            context.draw(
                Image(decorative: tile, scale: 1),
                in: CGRect(origin: .zero, size: size)
            )
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [.appTealDark, .appAmber], startPoint: .top, endPoint: .bottom)
        GrainOverlayView()
    }
    .ignoresSafeArea()
}
