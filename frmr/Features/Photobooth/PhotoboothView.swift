import PhotosUI
import SwiftData
import SwiftUI

// v5.2 S2 (user decision): Film strip mode keeps the camera's chrome
// identical to Photo. The four slots become a mini-strip in the last-photo
// thumbnail's place; tapping it opens a sheet with the slots, the gallery,
// Pick from Roll, Undo and Generate. Capture itself stays with the shutter.

/// A small paper tab of four 4:5 frames that fill as you shoot, with an
/// "n/4" badge. Square-ish and small, so it turns in place.
struct MiniStripButton: View {
    let viewModel: PhotoboothViewModel
    let action: () -> Void

    private typealias UI = Constants.CameraUI

    var body: some View {
        Button(action: action) {
            VStack(spacing: UI.miniStripFrameSpacing) {
                ForEach(0..<Constants.entriesPerStrip, id: \.self) { index in
                    MiniFrame(image: viewModel.image(at: index))
                }
            }
            .padding(UI.miniStripPadding)
            .frame(width: UI.miniStripWidth, height: UI.miniStripHeight)
            .background(Color.appCream, in: RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
            .overlay(alignment: .topTrailing) {
                // CONTRACT: a stripProgressBadge ("2/4") on PhotoboothViewModel
                Text("\(viewModel.shots.count)/\(viewModel.slotCount)")
                    .font(.frmrCode)
                    .foregroundStyle(Color.appBlack)
                    .padding(.horizontal, Constants.DesignUI.Space.xs)
                    .background(Color.appAmber, in: Capsule())
                    .fixedSize()
                    .offset(x: UI.miniStripBadgeOffset, y: -UI.miniStripBadgeOffset)
            }
            .frmrChromeTypeSize()
            .rotatingWithDevice()
            .frame(minWidth: Constants.DesignUI.targetMin, minHeight: Constants.DesignUI.targetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Strip, \(viewModel.stripProgressText) frames")
        .accessibilityHint("Opens the strip")
        .accessibilityIdentifier("strip.miniStrip")
        .frmrLargeContent("Strip", systemImage: "film.stack")
    }
}

private struct MiniFrame: View {
    let image: UIImage?

    var body: some View {
        Color.appBlack.opacity(Constants.CameraUI.stripEmptySlotOpacity)
            .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
    }
}

/// The strip's slots and its actions: four larger frames with the count,
/// then gallery, Pick from Roll and Undo as glass icons, and Generate as the
/// one amber primary (enabled from one frame).
struct StripSlotsSheet: View {
    @Bindable var viewModel: PhotoboothViewModel
    let onGenerate: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isRollPickerPresented = false

    private typealias UI = Constants.CameraUI
    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .darkroom, contrast: contrast) }

    var body: some View {
        VStack(spacing: Constants.DesignUI.Space.l) {
            Text("Captured \(viewModel.stripProgressText)")
                .font(.frmrLabel)
                .foregroundStyle(theme.textMuted)
                .accessibilityIdentifier("strip.count")

            HStack(spacing: UI.stripSlotSpacing) {
                ForEach(0..<Constants.entriesPerStrip, id: \.self) { index in
                    SlotView(image: viewModel.image(at: index), number: index + 1)
                }
            }

            HStack(spacing: Constants.DesignUI.Space.m) {
                PhotosPicker(
                    selection: $viewModel.pickerItems,
                    maxSelectionCount: max(viewModel.remainingSlots, 1),
                    matching: .images
                ) {
                    GlassIconGlyph(systemImage: "photo.on.rectangle", size: UI.sheetIconSize, rotates: false)
                }
                .accessibilityLabel("Choose photos from library")
                .accessibilityIdentifier("strip.gallery")
                .disabled(viewModel.isFull)
                .opacity(viewModel.isFull ? UI.disabledControlOpacity : 1)

                GlassIconButton(
                    systemImage: "film.stack",
                    label: "Pick from Roll",
                    identifier: "strip.pickRoll",
                    size: UI.sheetIconSize,
                    isDisabled: viewModel.isFull,
                    rotates: false,
                    action: { isRollPickerPresented = true }
                )

                GlassIconButton(
                    systemImage: "arrow.uturn.backward",
                    label: "Undo last photo",
                    identifier: "strip.undo",
                    size: UI.sheetIconSize,
                    isDisabled: !viewModel.hasShots,
                    rotates: false,
                    action: viewModel.removeLastShot
                )

                Button(action: onGenerate) {
                    Text("Generate")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .frmrPrimaryButtonStyle()
                .disabled(!viewModel.canGenerate)
                .accessibilityLabel("Generate strip")
                .accessibilityHint("Builds a strip from the photos so far")
                .accessibilityIdentifier("strip.generate")
            }
        }
        .padding(Constants.DesignUI.gutter)
        .foregroundStyle(theme.text)
        .frmrChromeTypeSize()
        .onChange(of: viewModel.pickerItems) {
            Task { await viewModel.loadPickerSelection() }
        }
        .sheet(isPresented: $isRollPickerPresented) {
            RollPickerSheet(remainingSlots: viewModel.remainingSlots, onPick: viewModel.add(rollPhoto:))
        }
        .presentationDetents([.height(UI.slotsSheetHeight)])
        .presentationDragIndicator(.visible)
        .frmrSheetBackground()
        .preferredColorScheme(.dark)
    }
}

private struct SlotView: View {
    let image: UIImage?
    let number: Int

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb) }

    var body: some View {
        Color.white.opacity(Constants.CameraUI.stripEmptySlotOpacity)
            .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text("\(number)")
                        .font(.frmrValue)
                        .foregroundStyle(.white.opacity(Constants.CameraUI.dialUnselectedOpacity))
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(image == nil ? "Frame \(number), empty" : "Frame \(number)")
            .accessibilityIdentifier("strip.slot")
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
        Array(repeating: GridItem(.flexible(), spacing: Constants.DesignUI.contactSheetGutter), count: Constants.CameraUI.rollPickerColumns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Constants.DesignUI.contactSheetGutter) {
                    ForEach(photos) { photo in
                        Button { pick(photo) } label: {
                            Color.clear
                                .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
                                .overlay { RollLookImage(photo: photo, contentMode: .fill) { Color.clear } }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .disabled(remainingSlots == 0)
                        .accessibilityLabel("Roll photo")
                        .accessibilityHint("Adds this photo to the strip")
                        .accessibilityIdentifier("strip.rollPicker.photo")
                    }
                }
                .padding(.horizontal, Constants.DesignUI.gutter)
            }
            .overlay {
                if photos.isEmpty {
                    ContentUnavailableView(
                        "Your roll is empty",
                        systemImage: "camera.aperture",
                        description: Text("Photos you save to the roll show up here.")
                    )
                    .accessibilityIdentifier("strip.rollPicker.empty")
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
        MiniStripButton(viewModel: PhotoboothViewModel(), action: {})
    }
}
