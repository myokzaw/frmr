import SwiftUI

// The rounded card of one coach mark: title, one line of body, and the
// controls — Skip on every step, plus Got it on the last (v3 F5)
struct CoachBubble: View {
    let title: String
    let bodyText: String
    let isLastStep: Bool
    let onSkip: () -> Void
    let onGotIt: () -> Void

    // Glass over the dark scrim, so the text is always light
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.Onboarding.bubbleInnerSpacing) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(Constants.Onboarding.bubbleBodyOpacity))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(Constants.Onboarding.bubbleBodyOpacity))

                Spacer()

                if isLastStep {
                    Button("Got it", action: onGotIt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAmber)
                }
            }
        }
        .padding(Constants.Onboarding.bubblePadding)
        .frame(maxWidth: Constants.Onboarding.bubbleMaxWidth, alignment: .leading)
        .frmrAdaptiveGlass(in: RoundedRectangle(cornerRadius: Constants.Onboarding.bubbleCornerRadius))
        .environment(\.colorScheme, .dark)
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
