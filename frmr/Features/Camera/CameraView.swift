import AVFoundation
import SwiftUI

struct CameraView: View {
    @Environment(ErrorState.self) private var errorState
    @Environment(OnboardingViewModel.self) private var onboarding
    @State private var viewModel = CameraViewModel()
    @State private var photobooth = PhotoboothViewModel()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            viewfinder

            // DELIBERATE TEMPORARY SAFETY NET: under the portrait lock this
            // branch never runs. Remove it (and dockedChrome) once the lock is
            // verified on a physical device.
            // Compact height means the interface itself is landscape (only
            // possible if the portrait lock did not hold, or is lifted by
            // decision). The system has already turned the screen, so the
            // counter-rotation is zeroed there or glyphs would turn twice.
            if verticalSizeClass == .compact {
                dockedChrome
                    .environment(\.deviceRotation, .zero)
            } else {
                portraitChrome
            }

            PermissionDeniedOverlay(isVisible: viewModel.isPermissionDenied)
                .rotatingWithDevice()

            chromeDebugOverlay
        }
        .environment(\.deviceRotation, viewModel.uiRotationAngle)
        .task {
            viewModel.errorState = errorState
            photobooth.errorState = errorState
            await viewModel.startCamera()
            // startCamera suspends on the system permission dialog, so by here
            // it has been answered either way — the walkthrough may now run
            // (v3 F5; it runs on denial too, Library/Settings still matter)
            onboarding.notePermissionResolved()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        .fullScreenCover(isPresented: Bindable(viewModel).isEditorPresented.projectedValue) {
            EntryEditorView(camera: viewModel)
        }
        .fullScreenCover(isPresented: Bindable(photobooth).isStripPresented.projectedValue) {
            StripView(items: photobooth.stripItems, isPhotobooth: true, onDone: photobooth.clear)
        }
    }

    private var portraitChrome: some View {
        // Portrait positions are the only positions. In landscape each
        // control turns about its own centre (rotatingWithDevice) and
        // nothing moves, stacks or reflows.
        VStack {
            ModeToggle(
                isDiaryActive: viewModel.isDiaryMode,
                onSelectDiary: viewModel.selectDiaryMode,
                onSelectPhotobooth: viewModel.selectPhotoboothMode
            )
            .padding(.top)

            if viewModel.isPhotoboothMode {
                PhotoboothView(viewModel: photobooth)
                    .padding(.top)
            }

            Spacer()

            VStack(spacing: Constants.CameraUI.chipSpacing) {
                if viewModel.isLensSelectorVisible {
                    LensChipRow(
                        lenses: viewModel.availableLenses,
                        selected: viewModel.selectedLens,
                        onSelect: viewModel.selectLens
                    )
                }

                WhiteBalanceControl(
                    selected: viewModel.whiteBalance,
                    isExpanded: viewModel.isWhiteBalanceExpanded,
                    onToggle: viewModel.toggleWhiteBalanceExpansion,
                    onSelect: viewModel.selectWhiteBalance
                )

                // A circle looks identical at any angle, so the shutter
                // itself never rotates.
                ZStack {
                    ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                        .padding(.trailing, Constants.EditorUI.buttonPadding)
                }
                .padding(.bottom, Constants.CameraUI.shutterBottomPadding)
            }
        }
    }

    // Far-right dock, like the system Camera in landscape. Anchored with an
    // overlay on a non-rotating parent so nothing swings when the screen turns.
    private var dockedChrome: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                VStack(spacing: Constants.CameraUI.dockSpacing) {
                    ModeToggle(
                        isDiaryActive: viewModel.isDiaryMode,
                        onSelectDiary: viewModel.selectDiaryMode,
                        onSelectPhotobooth: viewModel.selectPhotoboothMode
                    )
                    if viewModel.isLensSelectorVisible {
                        LensChipRow(
                            lenses: viewModel.availableLenses,
                            selected: viewModel.selectedLens,
                            onSelect: viewModel.selectLens
                        )
                    }
                    WhiteBalanceControl(
                        selected: viewModel.whiteBalance,
                        isExpanded: viewModel.isWhiteBalanceExpanded,
                        onToggle: viewModel.toggleWhiteBalanceExpansion,
                        onSelect: viewModel.selectWhiteBalance
                    )
                    ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                }
                .padding(.trailing, Constants.CameraUI.dockTrailingPadding)
            }
            .overlay(alignment: .bottom) {
                if viewModel.isPhotoboothMode {
                    PhotoboothView(viewModel: photobooth)
                }
            }
    }

    // v3 F1 step 3: proves on a device photograph which values actually reach
    // this view. Off unless Constants.CameraUI.chromeDebugOverlayEnabled.
    @ViewBuilder private var chromeDebugOverlay: some View {
        #if DEBUG
        if Constants.CameraUI.chromeDebugOverlayEnabled {
            Text("angle: \(Int(viewModel.uiRotationAngle.degrees))°")
                .font(.system(size: Constants.CameraUI.captionFontSize, design: .monospaced))
                .foregroundStyle(.yellow)
                .padding(4)
                .background(.black.opacity(0.6))
        }
        #endif
    }

    // The live preview plus everything that reacts to touching it (v2 F1–F3, F6).
    // Gestures live on the preview itself so tap coordinates match the layer's
    // geometry with no conversion of our own.
    private var viewfinder: some View {
        CameraPreview(session: viewModel.session, onLayerReady: viewModel.registerPreviewLayer)
            .overlay(GrainOverlayView())
            .overlay(alignment: .topLeading) {
                if let point = viewModel.focusPoint {
                    // Rotate about the indicator's own centre first, then place
                    // it; positioning first would pivot about the whole overlay.
                    FocusIndicatorView()
                        .rotatingWithDevice()
                        .position(point)
                        // A fresh identity per tap restarts the draw-in animation
                        .id(focusIndicatorID(for: point))
                }
            }
            .overlay(alignment: .trailing) {
                if viewModel.isExposureIndicatorVisible {
                    ExposureIndicatorView(exposureBias: viewModel.exposureBias)
                        .rotatingWithDevice()
                        .padding(.trailing, Constants.Camera.exposureIndicatorPadding)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: viewModel.isExposureIndicatorVisible)
            .contentShape(Rectangle())
            .gesture(exposureDrag)
            .gesture(pinchZoom)
            .onTapGesture(count: 2) { viewModel.resetZoom() }
            .onTapGesture { location in viewModel.userTapped(at: location) }
            .ignoresSafeArea()
    }

    private var exposureDrag: some Gesture {
        DragGesture()
            .onChanged { value in viewModel.exposureDragChanged(translationHeight: value.translation.height) }
            .onEnded { _ in viewModel.exposureDragEnded() }
    }

    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { value in viewModel.pinchChanged(scale: value.magnification) }
            .onEnded { _ in viewModel.pinchBegan() }
    }

    private func focusIndicatorID(for point: CGPoint) -> String {
        "\(point.x)-\(point.y)"
    }

    private func shutterTapped() {
        Task {
            if viewModel.isDiaryMode {
                await viewModel.captureForDiary()
            } else if let shot = await viewModel.captureForPhotobooth() {
                photobooth.add(shot)
            }
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    // The view model needs the layer to turn a tap into a device point (v2 F1)
    let onLayerReady: (AVCaptureVideoPreviewLayer) -> Void

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        if let layer = view.previewLayer {
            onLayerReady(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// A static capsule holding two square icon segments. The capsule never
// rotates — it is wider than tall — only the glyph inside each segment does.
private struct ModeToggle: View {
    let isDiaryActive: Bool
    let onSelectDiary: () -> Void
    let onSelectPhotobooth: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ModeSegment(systemImage: "book.closed", label: "Diary", isActive: isDiaryActive, action: onSelectDiary)
            ModeSegment(systemImage: "film", label: "Film strip", isActive: !isDiaryActive, action: onSelectPhotobooth)
        }
        .padding(Constants.CameraUI.modePillPadding)
        .background(.white.opacity(Constants.CameraUI.chipInactiveOpacity), in: Capsule())
    }
}

private struct ModeSegment: View {
    let systemImage: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    private var background: Color {
        isActive ? .white : .clear
    }

    private var foreground: Color {
        isActive ? .appBlack : .white
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Constants.CameraUI.chipIconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.chipDiameter, height: Constants.CameraUI.chipDiameter)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct ShutterButton: View {
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
    }
}

private struct LensChipRow: View {
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

// Its screen position comes from the non-rotating `.overlay(alignment:
// .trailing)` at the call site; only the icon inside the static disc rotates.
private struct FlipCameraButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .foregroundStyle(.white)
                .rotatingWithDevice()
                .frame(
                    width: Constants.CameraUI.secondaryButtonSize,
                    height: Constants.CameraUI.secondaryButtonSize
                )
                .background(.white.opacity(Constants.CameraUI.chipInactiveOpacity), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Flip camera")
        .opacity(isVisible ? 1 : 0)
        .disabled(!isVisible)
    }
}

private struct PermissionDeniedOverlay: View {
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
