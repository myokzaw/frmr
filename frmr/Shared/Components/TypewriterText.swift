import SwiftUI

// Reveals text one character at a time (v2 F8b). The prompt arriving letter by
// letter makes it read as something being offered to the user, not a label.
//
// The reveal Task is owned by `.task`, so navigating away (Retake) cancels it
// cleanly — no Timer, no Combine, nothing to tear down by hand.
struct TypewriterText<Style: ShapeStyle>: View {
    let fullText: String
    let interval: TimeInterval
    let foregroundStyle: Style

    @State private var displayed = ""

    init(
        _ fullText: String,
        interval: TimeInterval = Constants.Diary.promptTypewriterInterval,
        foregroundStyle: Style
    ) {
        self.fullText = fullText
        self.interval = interval
        self.foregroundStyle = foregroundStyle
    }

    var body: some View {
        Text(displayed)
            .foregroundStyle(foregroundStyle)
            // Reserve the final layout up front so the surrounding form doesn't
            // reflow while characters land
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topLeading) {
                Text(fullText).hidden()
            }
            // Tapping skips the animation — never make someone wait on chrome
            .contentShape(Rectangle())
            .onTapGesture { displayed = fullText }
            .task(id: fullText) {
                displayed = ""
                await Self.reveal(fullText, interval: interval) { displayed = $0 }
            }
    }

    // Extracted so the reveal timing is testable without a view host.
    static func reveal(
        _ text: String,
        interval: TimeInterval,
        onUpdate: (String) -> Void
    ) async {
        var revealed = ""
        for character in text {
            revealed.append(character)
            onUpdate(revealed)
            // A cancellation here just means the view went away mid-reveal
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
        }
    }
}

#Preview {
    TypewriterText(
        "What were you trying to hold onto in this moment?",
        foregroundStyle: Color.appBlack
    )
    .font(.frmrPrompt)
    .padding()
}
