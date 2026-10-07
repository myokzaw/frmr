import SwiftUI

struct CharacterCountIndicator: View {
    let text: String
    let isVisible: Bool

    var body: some View {
        Text(text)
            .font(.system(size: Constants.EditorUI.charCountFontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.appOrange)
            .opacity(isVisible ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#Preview {
    CharacterCountIndicator(text: "128/280", isVisible: true)
        .padding()
}
