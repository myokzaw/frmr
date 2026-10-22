import PhotosUI
import SwiftData
import SwiftUI

// v5.1 F9: the strip layer of the camera (Film strip mode). The camera chrome
// around it is identical to Photo mode; this adds, just above the dial, four
// compact slot thumbnails under an "n of 4" count, with the gallery picker,
// Pick from Roll and undo as small glass icons beside them. Generate lives in
// the shutter row (GenerateStripButton). Capture itself stays with
// CameraView's shutter. Square slots and round icons turn individually
// (rotatingWithDevice); the count is a short upright status line.
struct PhotoboothView: View {
    @Bindable var viewModel: PhotoboothViewModel
    @State private var isRollPickerPresented = false

    private var countText: String {
        "\(viewModel.shots.count) of \(viewModel.slotCount)"
    }

    var body: some View {
        VStack(spacing: Constants.CameraUI.stripCountSpacing) {
            Text(countText)
                .font(.system(size: Constants.CameraUI.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(Constants.CameraUI.dialNameOpacity))
                .accessibilityLabel("Captured \(countText)")
                .accessibilityIdentifier("strip.count")

            HStack(spacing: Constants.CameraUI.stripSlotSpacing) {
                ForEach(0..<Constants.entriesPerStrip, id: \.self) { index in
                    SlotView(image: viewModel.image(at: index))
                        .rotatingWithDevice()
                }
                Spacer(minLength: Constants.CameraUI.chipSpacing)
                PhotosPicker(
                    selection: $viewModel.pickerItems,
                    maxSelectionCount: max(viewModel.remainingSlots, 1),
                    matching: .images
                ) {
                    GlassIconGlyph(systemImage: "photo.on.rectangle", size: Constants.ScrubberUI.glassButtonSmallSize)
                }
                .accessibilityLabel("Choose photos from library")
                .accessibilityIdentifier("strip.gallery")
                .disabled(viewModel.isFull)

                GlassIconButton(
                    systemImage: "film.stack",
                    label: "Pick from Roll",
                    identifier: "strip.pickRoll",
                    size: Constants.ScrubberUI.glassButtonSmallSize,
                    isDisabled: viewModel.isFull,
                    action: { isRollPickerPresented = true }
                )

                GlassIconButton(
                    systemImage: "arrow.uturn.backward",
                    label: "Undo last photo",
                    identifier: "strip.undo",
                    size: Constants.ScrubberUI.glassButtonSmallSize,
                    isDisabled: !viewModel.hasShots,
                    action: viewModel.removeLastShot
                )
            }
        }
        .padding(.horizontal, Constants.CameraUI.screenMargin)
        .onChange(of: viewModel.pickerItems) {
            Task { await viewModel.loadPickerSelection() }
        }
        .sheet(isPresented: $isRollPickerPresented) {
            RollPickerSheet(remainingSlots: viewModel.remainingSlots, onPick: pickFromRoll)
        }
    }

    // A Roll photo joins the strip as its original on the stock it was
    // edited with. CONTRACT REQUEST: PhotoboothViewModel.add(rollPhoto:) that
    // keeps the full look (print, effects).
    private func pickFromRoll(_ photo: RollPhoto) {
        guard let image = RollViewModel.loadPhoto(for: photo) else { return }
        viewModel.add(PhotoboothShot(image: image, filmStock: photo.look.stock))
    }
}

private struct SlotView: View {
    let image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: Constants.CameraUI.stripSlotCornerRadius)
            .fill(.white.opacity(Constants.CameraUI.stripEmptySlotOpacity))
            .frame(width: Constants.CameraUI.stripSlotSize, height: Constants.CameraUI.stripSlotSize)
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
                .frame(width: Constants.CameraUI.stripSlotSize, height: Constants.CameraUI.stripSlotSize)
                .clipShape(RoundedRectangle(cornerRadius: Constants.CameraUI.stripSlotCornerRadius))
        }
    }
}

// Primary in Film strip mode, once at least one slot is filled. A round
// amber disc with a glyph: a "Generate strip" pill is far wider than tall,
// so turning its label in place would overflow it.
struct GenerateStripButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: Constants.CameraUI.stripGenerateIconSize, weight: .bold))
                .foregroundStyle(Color.appBlack)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.stripGenerateSize, height: Constants.CameraUI.stripGenerateSize)
                .background(Color.appAmber, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate strip")
        .accessibilityHint("Builds a strip from the photos so far")
        .accessibilityIdentifier("strip.generate")
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
    }
}

// Pick from Roll: the Roll's photos in their looks; tap to add one to the
// strip, Done when finished. Closes itself once every slot is filled.
struct RollPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RollPhoto.capturedAt, order: .reverse) private var photos: [RollPhoto]

    let remainingSlots: Int
    let onPick: (RollPhoto) -> Void

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Constants.CameraUI.rollPickerSpacing), count: Constants.CameraUI.rollPickerColumns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if photos.isEmpty {
                    Text("Your roll is empty. Photos you save to the roll show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(Constants.CameraUI.sheetPadding)
                        .accessibilityIdentifier("strip.rollPicker.empty")
                } else {
                    LazyVGrid(columns: columns, spacing: Constants.CameraUI.rollPickerSpacing) {
                        ForEach(photos) { photo in
                            Button { pick(photo) } label: {
                                RollLookImage(photo: photo, contentMode: .fill) { Color.clear }
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: Constants.CameraUI.rollPickerCornerRadius))
                            }
                            .buttonStyle(.plain)
                            .disabled(remainingSlots == 0)
                            .accessibilityLabel("Roll photo")
                            .accessibilityHint("Adds this photo to the strip")
                            .accessibilityIdentifier("strip.rollPicker.photo")
                        }
                    }
                    .padding(Constants.CameraUI.rollPickerSpacing)
                }
            }
            .navigationTitle("Pick from Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("strip.rollPicker.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .frmrSheetBackground()
    }

    private func pick(_ photo: RollPhoto) {
        onPick(photo)
        if remainingSlots <= 1 { dismiss() }
    }
}

#Preview {
    ZStack {
        Color.black
        PhotoboothView(viewModel: PhotoboothViewModel())
    }
}
