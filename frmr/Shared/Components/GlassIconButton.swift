import SwiftUI

// v5.1 F10: a round icon button on glass, with an accessibility label.
// Used by the full-screen viewers' top bars.
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    var identifier: String?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Constants.DetailUI.topBarIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Constants.DetailUI.topBarButtonSize, height: Constants.DetailUI.topBarButtonSize)
                .frmrAdaptiveGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Constants.CameraUI.disabledControlOpacity)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}
