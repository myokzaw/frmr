import SwiftUI

// Sun icon + EV readout shown on the right edge while the user drags to
// adjust exposure compensation (v2 F2). Presentation only; the view model
// decides when it's visible.
struct ExposureIndicatorView: View {
    let exposureBias: Float

    // Signed, one decimal — "+0.7", "-1.3", "0.0"
    private var formattedBias: String {
        String(format: "%+.1f", exposureBias)
    }

    var body: some View {
        VStack(spacing: Constants.Camera.exposureIndicatorSpacing) {
            Image(systemName: "sun.max.fill")
            Text(formattedBias)
                .font(.system(size: Constants.Camera.exposureIndicatorFontSize, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(Color.appAmber)
        .padding(Constants.Camera.exposureIndicatorSpacing)
        .background(.black.opacity(Constants.CameraUI.chipInactiveOpacity), in: Capsule())
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.appBlack
        ExposureIndicatorView(exposureBias: 0.7)
    }
    .ignoresSafeArea()
}
