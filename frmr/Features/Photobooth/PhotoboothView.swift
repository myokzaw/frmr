import PhotosUI
import SwiftUI

// The photobooth overlay inside the camera screen: 4 capture slots, gallery
// picker, undo, and the generate CTA. Capture itself stays with CameraView's
// shutter; this view only reflects and controls the slot state. Nothing here
// rotates as a group — the square slots and icon buttons turn individually
// (rotatingWithDevice) and the wide generate button keeps a static backing
// shape with only its glyph turning.
struct PhotoboothView: View {
    @Bindable var viewModel: PhotoboothViewModel

    var body: some View {
        VStack(spacing: Constants.CameraUI.slotSpacing) {
            HStack(spacing: Constants.CameraUI.slotSpacing) {
                ForEach(0..<Constants.entriesPerStrip, id: \.self) { index in
                    SlotView(image: viewModel.image(at: index))
                        .rotatingWithDevice()
                }
            }

            Text(viewModel.capturedCountText)
                .font(.system(size: Constants.CameraUI.captionFontSize, design: .monospaced))
                .foregroundStyle(.white.opacity(Constants.CameraUI.captionOpacity))
                // Deliberate exception: a wide string cannot rotate in place
                // without swinging into the rows above and below, so the
                // caption stays an upright status line in every orientation.
                .lineLimit(1)
                .minimumScaleFactor(Constants.CameraUI.captionMinScale)
                .frame(maxWidth: Constants.CameraUI.captionMaxWidth)

            HStack(spacing: Constants.CameraUI.slotSpacing) {
                PhotosPicker(
                    selection: $viewModel.pickerItems,
                    maxSelectionCount: max(viewModel.remainingSlots, 1),
                    matching: .images
                ) {
                    SecondarySquareLabel(systemImage: "photo.on.rectangle")
                }
                .accessibilityLabel("Choose photos from library")
                .disabled(viewModel.isFull)

                GenerateStripButton(
                    isEnabled: viewModel.canGenerate,
                    action: { viewModel.isStripPresented = true }
                )

                Button(action: viewModel.removeLastShot) {
                    SecondarySquareLabel(systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo last photo")
                .disabled(!viewModel.hasShots)
            }
        }
        .onChange(of: viewModel.pickerItems) {
            Task { await viewModel.loadPickerSelection() }
        }
    }
}

private struct SlotView: View {
    let image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Constants.CameraUI.slotCornerRadius)
            .strokeBorder(
                .white.opacity(Constants.CameraUI.slotBorderOpacity),
                style: StrokeStyle(
                    lineWidth: Constants.CameraUI.slotDashWidth,
                    dash: [Constants.CameraUI.slotDashLength]
                )
            )
            .frame(width: Constants.CameraUI.slotSize, height: Constants.CameraUI.slotSize)
            .overlay(SlotImage(image: image))
    }
}

private struct SlotImage: View {
    let image: UIImage?

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Constants.CameraUI.slotSize, height: Constants.CameraUI.slotSize)
                .clipShape(RoundedRectangle(cornerRadius: Constants.CameraUI.slotCornerRadius))
        }
    }
}

private struct SecondarySquareLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.white)
            .rotatingWithDevice()
            .frame(
                width: Constants.CameraUI.secondaryButtonSize,
                height: Constants.CameraUI.secondaryButtonSize
            )
            .background(
                RoundedRectangle(cornerRadius: Constants.CameraUI.secondaryButtonCornerRadius)
                    .strokeBorder(
                        .white.opacity(Constants.CameraUI.slotBorderOpacity),
                        lineWidth: Constants.CameraUI.slotDashWidth
                    )
            )
    }
}

// Icon-only on a round amber disc: a "Generate strip" pill is far wider than
// tall, so turning its label in place would overflow the pill.
private struct GenerateStripButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: Constants.CameraUI.chipIconSize, weight: .bold))
                .foregroundStyle(Color.appBlack)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.chipDiameter, height: Constants.CameraUI.chipDiameter)
                .background(Color.appAmber, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate strip")
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Constants.CameraUI.disabledControlOpacity)
    }
}

#Preview {
    ZStack {
        Color.black
        PhotoboothView(viewModel: PhotoboothViewModel())
    }
}
