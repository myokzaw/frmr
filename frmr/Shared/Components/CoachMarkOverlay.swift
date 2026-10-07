import SwiftUI

// The full-screen walkthrough overlay: scrim, bubble, arrow (v3 F5).
// Portrait-only by construction — the caller passes step: nil in landscape,
// so nothing here ever enters the counter-rotation system.
struct CoachMarkOverlay: View {
    // nil hides the overlay entirely
    let step: CoachStep?
    let anchors: [CoachStep: Anchor<CGRect>]
    let onAdvance: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            if let step, let anchor = anchors[step] {
                marks(for: step, target: proxy[anchor], in: proxy.size)
            }
        }
        .animation(
            .easeInOut(duration: Constants.Onboarding.stepTransitionDuration),
            value: step
        )
    }

    @ViewBuilder
    private func marks(for step: CoachStep, target: CGRect, in screen: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // The tap that advances lives on the scrim itself; the highlighted
            // icon is NOT tappable through it — landing on a different tab
            // mid-sequence would break the walkthrough
            Color.black.opacity(Constants.Onboarding.scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onAdvance)

            CoachArrow()
                .stroke(.white, style: StrokeStyle(
                    lineWidth: Constants.Onboarding.arrowStroke,
                    lineCap: .round,
                    lineJoin: .round
                ))
                .frame(
                    width: Constants.Onboarding.arrowLength,
                    height: Constants.Onboarding.arrowLength
                )
                .position(
                    x: target.midX,
                    y: arrowBottomY(above: target) - Constants.Onboarding.arrowLength / 2
                )

            // Bottom-aligned inside a container whose bottom edge sits at the
            // top of the arrow, so the bubble's own (content-driven) height
            // never needs measuring
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                CoachBubble(
                    title: CoachCopy.entries[step]?.title ?? "",
                    bodyText: CoachCopy.entries[step]?.body ?? "",
                    isLastStep: step.next == nil,
                    onSkip: onSkip,
                    onGotIt: onAdvance
                )
            }
            .frame(height: bubbleBottomY(above: target), alignment: .bottom)
            .position(
                x: bubbleCenterX(pointingAt: target.midX, screenWidth: screen.width),
                y: bubbleBottomY(above: target) / 2
            )
        }
        .transition(.opacity)
        .id(step)
    }

    // MARK: Placement (pure, screen-frame math)

    private func arrowBottomY(above target: CGRect) -> CGFloat {
        target.minY - Constants.Onboarding.bubbleTabGap
    }

    private func bubbleBottomY(above target: CGRect) -> CGFloat {
        arrowBottomY(above: target) - Constants.Onboarding.arrowLength
    }

    // Horizontally clamped so the bubbles for the edge tabs stay on screen
    private func bubbleCenterX(pointingAt targetX: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let halfWidth = Constants.Onboarding.bubbleMaxWidth / 2
        let minX = Constants.Onboarding.bubbleEdgeInset + halfWidth
        let maxX = screenWidth - Constants.Onboarding.bubbleEdgeInset - halfWidth
        return min(max(targetX, minX), maxX)
    }
}
