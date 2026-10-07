import SwiftUI

// The rounded card of one coach mark: title, one line of body, and the
// controls — Skip on every step, plus Got it on the last (v3 F5)
struct CoachBubble: View {
    let title: String
    let bodyText: String
    let isLastStep: Bool
    let onSkip: () -> Void
    let onGotIt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Onboarding.bubbleInnerSpacing) {
            Text(title)
                .font(.system(size: Constants.Onboarding.bubbleTitleFontSize, weight: .semibold))
                .foregroundStyle(Color.appBlack)

            Text(bodyText)
                .font(.system(size: Constants.Onboarding.bubbleBodyFontSize))
                .foregroundStyle(Color.appBlack.opacity(Constants.Onboarding.bubbleBodyOpacity))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip", action: onSkip)
                    .font(.system(size: Constants.Onboarding.bubbleBodyFontSize))
                    .foregroundStyle(Color.appBlack.opacity(Constants.Onboarding.bubbleBodyOpacity))

                Spacer()

                if isLastStep {
                    Button("Got it", action: onGotIt)
                        .font(.system(size: Constants.Onboarding.bubbleBodyFontSize, weight: .semibold))
                        .foregroundStyle(Color.appTealDark)
                }
            }
        }
        .padding()
        .frame(maxWidth: Constants.Onboarding.bubbleMaxWidth, alignment: .leading)
        .background(
            .white,
            in: RoundedRectangle(cornerRadius: Constants.Onboarding.bubbleCornerRadius)
        )
    }
}

#Preview {
    ZStack {
        Color.black
        CoachBubble(
            title: "Library",
            bodyText: "Your saved entries and film strips live here.",
            isLastStep: true,
            onSkip: {},
            onGotIt: {}
        )
    }
}
