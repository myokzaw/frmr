import SwiftData
import SwiftUI

// The pieces of the camera's chrome (v5.1 F8/F9), shared by Photo and Film
// strip mode. Rotation rules throughout: each control turns its glyph about
// its own centre; wide controls keep a static backing.

// A small glass capsule with two square icon segments (v5.1-9): Photo and
// Film strip. The capsule never rotates — it is wider than tall — only the
// glyph inside each segment does.
struct ModeSwitch: View {
    let selected: CameraViewModel.Mode
    let onSelect: (CameraViewModel.Mode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraViewModel.Mode.allCases, id: \.self) { mode in
                ModeSegment(
                    systemImage: mode.symbolName,
                    label: mode.label,
                    identifier: "camera.mode.\(mode.identifierName)",
                    isActive: mode == selected,
                    action: { onSelect(mode) }
                )
            }
        }
        .padding(Constants.CameraUI.modeSwitchPadding)
        .frmrGlassCapsule()
    }
}

private extension CameraViewModel.Mode {
    var symbolName: String {
        switch self {
        case .photo: return "camera"
        case .photobooth: return "film"
        }
    }

    var identifierName: String {
        switch self {
        case .photo: return "photo"
        case .photobooth: return "filmstrip"
        }
    }
}

private struct ModeSegment: View {
    let systemImage: String
    let label: String
    let identifier: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Constants.CameraUI.chipIconSize, weight: .semibold))
                .foregroundStyle(isActive ? Color.appBlack : .white)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.modeSegmentSize, height: Constants.CameraUI.modeSegmentSize)
                .background(isActive ? Color.appAmber : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// The WB and EV buttons, small glass icons at the top right. A tint says the
// value is off its default; the full value is in the sheet and VoiceOver.
struct CameraControlButtons: View {
    let whiteBalanceText: String
    let exposureText: String
    let isWhiteBalanceAdjusted: Bool
    let isExposureAdjusted: Bool
    let onToggleWhiteBalance: () -> Void
    let onToggleExposure: () -> Void

    var body: some View {
        HStack(spacing: Constants.CameraUI.topButtonSpacing) {
            GlassIconButton(
                systemImage: "thermometer.medium",
                label: "White balance",
                identifier: "camera.wb.chip",
                value: whiteBalanceText,
                size: Constants.CameraUI.topButtonSize,
                foreground: isWhiteBalanceAdjusted ? .appAmber : .white,
                action: onToggleWhiteBalance
            )
            .accessibilityHint("Opens the white balance controls")
            GlassIconButton(
                systemImage: "plusminus",
                label: "Exposure compensation",
                identifier: "camera.ev.chip",
                value: exposureText,
                size: Constants.CameraUI.topButtonSize,
                foreground: isExposureAdjusted ? .appAmber : .white,
                action: onToggleExposure
            )
            .accessibilityHint("Opens the exposure controls")
        }
    }
}

// WB and EV share one glass sheet whose content follows the open panel. The
// viewfinder stays live above it and a tap there closes it.
struct CameraControlSheet: View {
    let viewModel: CameraViewModel

    private var height: CGFloat {
        viewModel.isWhiteBalanceExpanded
            ? Constants.CameraUI.whiteBalanceSheetHeight
            : Constants.CameraUI.exposureSheetHeight
    }

    var body: some View {
        VStack {
            if viewModel.isWhiteBalanceExpanded {
                WhiteBalancePanel(
                    activePreset: viewModel.activeWhiteBalancePreset,
                    kelvin: viewModel.whiteBalanceKelvin,
                    tint: viewModel.whiteBalanceTint,
                    valueText: viewModel.whiteBalanceChipText,
                    onPreset: viewModel.chooseWhiteBalancePreset,
                    onKelvin: viewModel.setWhiteBalanceKelvin,
                    onTint: viewModel.setWhiteBalanceTint
                )
            } else {
                ExposurePanel(
                    bias: viewModel.exposureBias,
                    readout: viewModel.exposureReadout,
                    onBias: viewModel.setExposureBias,
                    onStep: viewModel.stepExposureBias(by:)
                )
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Constants.CameraUI.sheetPadding)
        .padding(.top, Constants.CameraUI.sheetPadding)
        .presentationDetents([.height(height)])
        .presentationBackgroundInteraction(.enabled)
        .presentationDragIndicator(.visible)
        .frmrSheetBackground()
        .preferredColorScheme(.dark)
    }
}

struct ShutterButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.appAmber)
                .frame(
                    width: Constants.CameraUI.shutterInnerDiameter,
                    height: Constants.CameraUI.shutterInnerDiameter
                )
                .frame(
                    width: Constants.CameraUI.shutterOuterDiameter,
                    height: Constants.CameraUI.shutterOuterDiameter
                )
                .overlay(
                    Circle().strokeBorder(.white, lineWidth: Constants.CameraUI.shutterRingWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Shutter")
        .accessibilityIdentifier("camera.shutter")
    }
}

struct LensChipRow: View {
    let lenses: [CameraLens]
    let selected: CameraLens
    let onSelect: (CameraLens) -> Void

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            ForEach(lenses) { lens in
                CameraChip(label: lens.label, isSelected: lens == selected, action: { onSelect(lens) })
            }
        }
    }
}

// v5: the newest Roll photo, at the shutter's left. Tapping opens that
// photo's editor (re-edit mode) right here, so the next shot is one Save
// away; the whole Roll is in the Library. Hidden, but still taking its
// space, while the Roll is empty. The square keeps its shape in landscape:
// only the picture inside turns, so it reads upright.
struct LastPhotoButton: View {
    @Environment(ErrorState.self) private var errorState
    @Query(LastPhotoButton.newestPhoto) private var newest: [RollPhoto]
    @State private var edit: PhotoEditViewModel?

    private static var newestPhoto: FetchDescriptor<RollPhoto> {
        var descriptor = FetchDescriptor<RollPhoto>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        Group {
            if let photo = newest.first {
                Button { open(photo) } label: {
                    RollLookImage(photo: photo, contentMode: .fill) { Color.clear }
                        .rotatingWithDevice()
                        .frame(width: Constants.CameraUI.lastPhotoSize, height: Constants.CameraUI.lastPhotoSize)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.CameraUI.lastPhotoCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Constants.CameraUI.lastPhotoCornerRadius)
                                .strokeBorder(.white.opacity(Constants.CameraUI.lastPhotoBorderOpacity), lineWidth: Constants.CameraUI.lastPhotoBorderWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Last photo")
                .accessibilityHint("Opens your most recent photo to edit")
                .accessibilityIdentifier("camera.lastPhoto")
            } else {
                Color.clear
                    .frame(width: Constants.CameraUI.lastPhotoSize, height: Constants.CameraUI.lastPhotoSize)
            }
        }
        .fullScreenCover(item: $edit) { session in
            PhotoEditView(edit: session)
        }
    }

    private func open(_ photo: RollPhoto) {
        guard let session = PhotoEditViewModel(editing: photo) else {
            errorState.raise(.persistenceFailed(reason: "This photo's file couldn't be read."))
            return
        }
        session.onFinish = { _ in edit = nil }
        edit = session
    }
}

// Its screen position comes from the non-rotating `.overlay(alignment:
// .trailing)` at the call site; only the icon inside the static disc rotates.
struct FlipCameraButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        GlassIconButton(
            systemImage: "arrow.triangle.2.circlepath.camera",
            label: "Flip camera",
            identifier: "camera.flip",
            action: action
        )
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
    }
}

struct PermissionDeniedOverlay: View {
    let isVisible: Bool

    var body: some View {
        Text("Camera access is off. Enable it in Settings to take photos.")
            .font(.system(size: Constants.CameraUI.captionFontSize, design: .monospaced))
            .foregroundStyle(.white.opacity(Constants.CameraUI.captionOpacity))
            .multilineTextAlignment(.center)
            // Bounded so the turned text (width becomes height) always stays
            // on screen in landscape.
            .frame(maxWidth: Constants.CameraUI.permissionTextMaxWidth)
            .minimumScaleFactor(Constants.CameraUI.permissionTextMinScale)
            .padding()
            .opacity(isVisible ? 1 : 0)
    }
}

// The single full-screen cover for a Photo-mode shot (v5.1 F4): the editor,
// then — after Continue to diary — the prompt screen in the SAME cover. Two
// covers would have to dismiss one and present the other in one update,
// which SwiftUI drops; swapping the content never leaves the cover.
struct EditorFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let camera: CameraViewModel

    var body: some View {
        ZStack {
            if camera.isEditorPresented {
                EntryEditorView(camera: camera)
                    .transition(.opacity)
            } else if let edit = camera.photoEdit {
                PhotoEditView(edit: edit)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Constants.PhotoEditUI.animationDuration), value: camera.isEditorPresented)
    }
}
