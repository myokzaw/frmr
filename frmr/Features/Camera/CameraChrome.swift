import SwiftData
import SwiftUI

// The pieces of the camera's chrome (v5.1 F8/F9, v5.2 S1), shared by Photo
// and Film strip mode. Rotation rules throughout: each control turns its
// glyph about its own centre; wide controls keep a static backing. Chrome
// text is capped at the first accessibility size; glyph buttons offer the
// Large Content Viewer instead.

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
                .font(.system(size: Constants.CameraUI.chipIconSize, weight: .medium))
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
        .frmrLargeContent(LocalizedStringKey(label), systemImage: systemImage)
    }
}

// The WB and EV buttons, small glass discs at the top right in one group.
// Off its default, a button shows its value ("4300K", "+0.3") instead of
// its glyph, so the state is visible without opening the sheet (S1).
struct CameraControlButtons: View {
    let whiteBalanceText: String
    let exposureText: String
    let isWhiteBalanceAdjusted: Bool
    let isExposureAdjusted: Bool
    let onToggleWhiteBalance: () -> Void
    let onToggleExposure: () -> Void

    var body: some View {
        FrmrGlassContainer(spacing: Constants.CameraUI.topButtonSpacing) {
            HStack(spacing: Constants.CameraUI.topButtonSpacing) {
                ValueGlassButton(
                    systemImage: "thermometer.medium",
                    valueText: isWhiteBalanceAdjusted ? whiteBalanceText : nil,
                    label: "White balance",
                    value: whiteBalanceText,
                    identifier: "camera.wb.chip",
                    action: onToggleWhiteBalance
                )
                .accessibilityHint("Opens the white balance controls")
                ValueGlassButton(
                    systemImage: "plusminus",
                    valueText: isExposureAdjusted ? exposureText : nil,
                    label: "Exposure compensation",
                    value: exposureText,
                    identifier: "camera.ev.chip",
                    action: onToggleExposure
                )
                .accessibilityHint("Opens the exposure controls")
            }
        }
    }
}

/// A 44-pt glass disc showing a glyph, or a short value in `.frmrCode`
/// once the setting is off its default. Square, so it turns in place.
private struct ValueGlassButton: View {
    let systemImage: String
    let valueText: String?
    let label: String
    let value: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ButtonFace(systemImage: systemImage, valueText: valueText)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.topButtonSize, height: Constants.CameraUI.topButtonSize)
                .frmrGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
        .frmrLargeContent(LocalizedStringKey(label), systemImage: systemImage)
    }
}

private struct ButtonFace: View {
    let systemImage: String
    let valueText: String?

    var body: some View {
        if let valueText {
            Text(valueText)
                .font(.frmrCode)
                .foregroundStyle(Color.appAmber)
                .lineLimit(1)
                .minimumScaleFactor(Constants.CameraUI.valueButtonMinScale)
                .padding(.horizontal, Constants.DesignUI.Space.xxs)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: Constants.ScrubberUI.glassButtonIconSize, weight: .medium))
                .foregroundStyle(.white)
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
        .frmrChromeTypeSize()
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
                .frame(width: Constants.DesignUI.shutterInner, height: Constants.DesignUI.shutterInner)
                .frame(width: Constants.DesignUI.shutterOuter, height: Constants.DesignUI.shutterOuter)
                .overlay(
                    Circle().strokeBorder(.white, lineWidth: Constants.CameraUI.shutterRingWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Shutter")
        .accessibilityIdentifier("camera.shutter")
        .frmrLargeContent("Shutter", systemImage: "camera.aperture")
    }
}

/// The lens capsule (0.5×/1×/2×). Each chip is a circle, so it turns in place.
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
        .frmrChromeTypeSize()
    }
}

// v5.2 S1: a changed stock, EV or lens flashes large in the upper third of
// the viewfinder, so nobody has to look at their thumb (Obscura pattern).
// Short text centred in open space: it turns as one label. Announced to
// VoiceOver only when it is running.
struct CameraHUD: View {
    let flash: CameraHUDFlash?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private typealias Motion = Constants.DesignUI.Motion

    var body: some View {
        Text(flash?.text ?? "")
            .font(.frmrHUD)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(Constants.CameraUI.hudShadowOpacity), radius: Constants.CameraUI.hudShadowRadius)
            .frmrChromeTypeSize()
            .scaleEffect(FrmrMotion.hudScale(reduceMotion: reduceMotion, active: isVisible ? 1 : Constants.CameraUI.hudStartScale, resting: 1))
            .opacity(isVisible ? 1 : 0)
            .rotatingWithDevice()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("camera.hud")
            .task(id: flash) {
                guard let flash else { return }
                if UIAccessibility.isVoiceOverRunning {
                    AccessibilityNotification.Announcement(flash.text).post()
                }
                withAnimation(.easeOut(duration: Motion.hudFadeIn)) { isVisible = true }
                do {
                    try await Task.sleep(for: .seconds(Motion.hudFadeIn + Motion.hudHold))
                } catch {
                    return
                }
                withAnimation(.easeIn(duration: Motion.hudFadeOut)) { isVisible = false }
            }
    }
}

/// One HUD flash; a fresh id replays it even for the same text.
struct CameraHUDFlash: Equatable {
    let id = UUID()
    let text: String
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

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb) }

    var body: some View {
        Group {
            if let photo = newest.first {
                Button { open(photo) } label: {
                    RollLookImage(photo: photo, contentMode: .fill) { Color.clear }
                        .rotatingWithDevice()
                        .frame(width: Constants.CameraUI.lastPhotoSize, height: Constants.CameraUI.lastPhotoSize)
                        .clipShape(shape)
                        .overlay(
                            shape.strokeBorder(.white.opacity(Constants.CameraUI.lastPhotoBorderOpacity), lineWidth: Constants.CameraUI.lastPhotoBorderWidth)
                        )
                        // v5.2 §6.1: the new frame slides in, as the film advances
                        .id(photo.id)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
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
        .frmrAnimation(.snap, value: newest.first?.id)
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
        .frmrLargeContent("Flip camera", systemImage: "arrow.triangle.2.circlepath.camera")
    }
}

// v5.2 §5.11: camera access off, on the darkroom, with one way out
struct PermissionDeniedOverlay: View {
    let isVisible: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        if isVisible {
            ContentUnavailableView {
                Label("Camera access is off", systemImage: "camera")
                    .font(.frmrReading.weight(.semibold))
            } description: {
                Text("Turn it on in Settings to take photos.")
                    .font(.frmrMeta)
            } actions: {
                Button("Open Settings", action: openSettings)
                    .frmrPrimaryButtonStyle()
                    .accessibilityIdentifier("camera.openSettings")
            }
            .foregroundStyle(.white)
            .frame(maxWidth: Constants.CameraUI.permissionTextMaxWidth)
            .environment(\.colorScheme, .dark)
        }
    }

    // Opens this app's page in the iOS Settings app (a local URL, no network)
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// The single full-screen cover for a Photo-mode shot (v5.1 F4): the editor,
// then — after Continue to diary — the prompt screen in the SAME cover. Two
// covers would have to dismiss one and present the other in one update,
// which SwiftUI drops; swapping the content never leaves the cover. The
// darkroom crossfades to paper (panel motion; a plain crossfade under
// Reduce Motion).
struct EditorFlowView: View {
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
        .frmrAnimation(.panel, value: camera.isEditorPresented)
    }
}
