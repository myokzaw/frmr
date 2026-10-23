import SwiftUI

// The square that draws in and fades out where the user tapped to focus
// (v2 F1). Pure presentation — the view model owns when it appears and clears.
// Reduce Motion skips the draw-in and keeps only the fade (v5.2 M7).
struct FocusIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale = Constants.Camera.focusIndicatorAppearScale
    @State private var opacity: Double = 1

    var body: some View {
        Rectangle()
            .strokeBorder(.white, lineWidth: Constants.Camera.focusIndicatorStroke)
            .frame(
                width: Constants.Camera.focusIndicatorSize,
                height: Constants.Camera.focusIndicatorSize
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: Constants.Camera.focusIndicatorAppearDuration)) {
                    scale = 1
                }
                withAnimation(
                    .easeOut(duration: Constants.Camera.focusIndicatorFadeDuration)
                        .delay(Constants.Camera.focusIndicatorHoldDuration)
                ) {
                    opacity = 0
                }
            }
    }
}

#Preview {
    ZStack {
        Color.appBlack
        FocusIndicatorView()
    }
    .ignoresSafeArea()
}
