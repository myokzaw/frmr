import SwiftUI

// Quiet metadata under the writing card (v5.1 F10): small, muted, and only
// there once the soft limit is near.
struct CharacterCountIndicator: View {
    let text: String
    let isVisible: Bool
    var color: Color = .appOrange

    var body: some View {
        Text(text)
            .font(.system(size: Constants.EditorUI.charCountFontSize, design: .monospaced))
            .foregroundStyle(color)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(!isVisible)
    }
}

#Preview {
    CharacterCountIndicator(text: "128/280", isVisible: true)
        .padding()
}
