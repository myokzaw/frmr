import SwiftUI

// OPEN: spec calls for the Newsreader typeface; using the system serif design
// until the font file is bundled (project.md §6)
struct PromptCard: View {
    let prompt: String
    let textColor: Color

    var body: some View {
        // v2 F8b: the prompt types itself out, so it reads as something being
        // offered rather than a label that was already there.
        TypewriterText(prompt, foregroundStyle: textColor)
            .font(.system(size: Constants.EditorUI.promptFontSize, weight: .medium, design: .serif))
            .italic()
    }
}

#Preview {
    PromptCard(prompt: "What made you take this picture?", textColor: .appBlack)
        .padding()
}
