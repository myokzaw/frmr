import SwiftUI

// Quiet metadata under the writing surface (v5.1 F10, v5.2 S4): small,
// muted, and only there once the soft limit is near. It turns the
// destructive role in the last few characters (the old burnt orange was
// 2.72:1 on cream), and VoiceOver hears it at those two moments.
struct CharacterCountIndicator: View {
    let text: String
    let isVisible: Bool
    let isWarning: Bool
    let color: Color
    let warningColor: Color

    /// Within the last `Constants.EditorUI.charCountWarningRemaining`
    /// characters of the limit.
    nonisolated static func isWarning(count: Int, limit: Int = Constants.entryCharacterLimit) -> Bool {
        count >= limit - Constants.EditorUI.charCountWarningRemaining
    }

    var body: some View {
        Text(text)
            .font(.frmrMeta.monospacedDigit())
            .foregroundStyle(isWarning ? warningColor : color)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel("\(text) characters")
            .accessibilityHidden(!isVisible)
            .accessibilityIdentifier("entry.count")
            .onChange(of: isWarning) { _, warning in
                if warning, UIAccessibility.isVoiceOverRunning {
                    AccessibilityNotification.Announcement("\(text) characters").post()
                }
            }
    }
}

#Preview {
    CharacterCountIndicator(text: "128/280", isVisible: true, isWarning: false, color: .gray, warningColor: .red)
        .padding()
}
