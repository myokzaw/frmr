import SwiftUI

// The camera screen is locked to portrait, so the interface never turns when
// the phone does. Each control instead rotates about its own centre to stay
// upright for the person holding the phone, exactly like the system Camera.
// The angle arrives through the environment (set once on CameraView's root)
// so glyphs buried inside shared components don't need it threaded through.
private struct DeviceRotationKey: EnvironmentKey {
    static let defaultValue: Angle = .zero
}

extension EnvironmentValues {
    var deviceRotation: Angle {
        get { self[DeviceRotationKey.self] }
        set { self[DeviceRotationKey.self] = newValue }
    }
}

private struct RotatingWithDevice: ViewModifier {
    @Environment(\.deviceRotation) private var angle

    func body(content: Content) -> some View {
        content
            .rotationEffect(angle)
            .animation(.easeInOut(duration: Constants.Camera.orientationRotationDuration), value: angle)
    }
}

extension View {
    // Apply to a glyph or a roughly square control, never to a container and
    // never to something much wider than tall: rotationEffect repaints without
    // reflowing, so a wide view swings its ends into its neighbours. Wide
    // controls keep a static backing shape and rotate only the glyph inside.
    // The angle should be unwrapped (see CameraViewModel.uiRotationAngle) so
    // the animation always takes the shortest arc.
    func rotatingWithDevice() -> some View {
        modifier(RotatingWithDevice())
    }
}
