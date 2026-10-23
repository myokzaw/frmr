import SwiftUI

// v5.1 F8/F10: the glyph inside every round glass icon. On the camera it
// turns in place to stay upright (`rotates`); the disc itself is round and
// never moves. Used bare as a PhotosPicker label and inside GlassIconButton.
struct GlassIconGlyph: View {
    @Environment(\.deviceRotation) private var deviceRotation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let systemImage: String
    var size: CGFloat = Constants.ScrubberUI.glassButtonSize
    var foreground: Color = .white
    var rotates = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: Constants.ScrubberUI.glassButtonIconSize, weight: .medium))
            .foregroundStyle(foreground)
            .rotationEffect(rotates ? deviceRotation : .zero)
            .animation(reduceMotion ? nil : .easeInOut(duration: Constants.Camera.orientationRotationDuration), value: deviceRotation)
            .frame(width: size, height: size)
            .frmrGlass(in: Circle())
            .contentShape(Circle())
    }
}

// The one round icon button every screen shares (camera, editor, strip
// screen, viewers): a glass disc with an SF Symbol. Icon-only, so the label
// carries the meaning for VoiceOver. Merged from the v5.1 camera and restyle
// branches: `isEnabled` is the restyle spelling of `!isDisabled`.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    var value = ""
    var size: CGFloat = Constants.ScrubberUI.glassButtonSize
    var foreground: Color = .white
    var isDisabled = false
    var isEnabled = true
    var rotates = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassIconGlyph(systemImage: systemImage, size: size, foreground: foreground, rotates: rotates)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || !isEnabled)
        .opacity(isDisabled || !isEnabled ? Constants.CameraUI.disabledControlOpacity : 1)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}
