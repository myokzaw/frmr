import AVFoundation
import SwiftData
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
            #if DEBUG
            // UI tests only: the simulator has no camera, so the edit step is
            // reached through a fixture capture instead
            if PhotoEditFixture.isRequested {
                PhotoEditFixture.open(in: viewModel)
                return
            }
            #endif
            await viewModel.startCamera()
            // startCamera suspends on the system permission dialog, so by here
            // it has been answered either way — the walkthrough may now run
            // (v3 F5; it runs on denial too, Library/Settings still matter)
            onboarding.notePermissionResolved()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        // v5.1 F8: white balance and exposure open as glass sheets
        .sheet(isPresented: controlSheetPresented) {
            CameraControlSheet(viewModel: viewModel)
        }
        // v5 F4 / v5.1 F4: one cover for a shot's editor and, after
        // Continue to diary, the prompt screen (see EditorFlowView)
        .fullScreenCover(isPresented: editorFlowPresented) {
            EditorFlowView(camera: viewModel)
        }
        .fullScreenCover(isPresented: Bindable(photobooth).isStripPresented.projectedValue) {
            StripView(items: photobooth.stripItems, isPhotobooth: true, onDone: photobooth.clear)
        }
    }

    private var portraitChrome: some View {
        // Portrait positions are the only positions. In landscape each
        // control turns about its own centre (rotatingWithDevice) and
        // nothing moves, stacks or reflows. Photo and Film strip share every
        // piece; Film strip adds its slot layer above the dial.
        VStack {
            topBar
                .padding(.horizontal, Constants.CameraUI.screenMargin)
                .padding(.top, Constants.CameraUI.topBarTopPadding)

            Spacer()

            VStack(spacing: Constants.CameraUI.bottomStackSpacing) {
                if viewModel.isLensSelectorVisible {
                    LensChipRow(
                        lenses: viewModel.availableLenses,
                        selected: viewModel.selectedLens,
                        onSelect: viewModel.selectLens
                    )
                }

                if viewModel.isPhotoboothMode {
                    PhotoboothView(viewModel: photobooth)
                }

                StockDial(selected: viewModel.filmStock, onSelect: viewModel.selectFilmStock)
                    .padding(.horizontal, Constants.CameraUI.screenMargin)

                // A circle looks identical at any angle, so the shutter
                // itself never rotates.
                ZStack {
                    ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { leadingAccessory }
                .overlay(alignment: .trailing) {
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                        .padding(.trailing, Constants.EditorUI.buttonPadding)
                }
                .padding(.bottom, Constants.CameraUI.shutterBottomPadding)
            }
        }
    }

    // Mode switch at the top left, WB and EV at the top right (v5.1-9)
    private var topBar: some View {
        HStack {
            ModeSwitch(selected: viewModel.mode, onSelect: selectMode)
            Spacer()
            controlButtons
        }
    }

    private var controlButtons: some View {
        CameraControlButtons(
            whiteBalanceText: viewModel.whiteBalanceChipText,
            exposureText: viewModel.exposureReadout,
            isWhiteBalanceAdjusted: viewModel.isWhiteBalanceAdjusted,
            isExposureAdjusted: viewModel.isExposureAdjusted,
            onToggleWhiteBalance: viewModel.toggleWhiteBalanceExpansion,
            onToggleExposure: viewModel.toggleExposurePanel
        )
    }

    // Photo: the newest Roll photo. Film strip: Generate, once a slot is
    // filled, in the same place (v5.1 F9).
    @ViewBuilder private var leadingAccessory: some View {
        if viewModel.isPhotoMode {
            LastPhotoButton()
                .padding(.leading, Constants.EditorUI.buttonPadding)
        } else {
            GenerateStripButton(isVisible: photobooth.canGenerate) { photobooth.isStripPresented = true }
                .padding(.leading, Constants.EditorUI.buttonPadding)
        }
    }

    // The panel slot is shared, so leaving a mode closes whatever was open
    private func selectMode(_ mode: CameraViewModel.Mode) {
        viewModel.closePanels()
        switch mode {
        case .photo: viewModel.selectPhotoMode()
        case .photobooth: viewModel.selectPhotoboothMode()
        }
    }

    // Far-right dock, like the system Camera in landscape. Anchored with an
    // overlay on a non-rotating parent so nothing swings when the screen turns.
    private var dockedChrome: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                VStack(spacing: Constants.CameraUI.dockSpacing) {
                    ModeSwitch(selected: viewModel.mode, onSelect: selectMode)
                    if viewModel.isLensSelectorVisible {
                        LensChipRow(
                            lenses: viewModel.availableLenses,
                            selected: viewModel.selectedLens,
                            onSelect: viewModel.selectLens
                        )
                    }
                    controlButtons
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

    // The sheet shows while WB or EV is the open panel; a drag-down or a
    // viewfinder tap closes it through the view model
    private var controlSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isWhiteBalanceExpanded || viewModel.isExposurePanelExpanded },
            set: { isPresented in
                if !isPresented { viewModel.closePanels() }
            }
        )
    }

    // Retake, Discard, Save and the diary prompt's Save / Skip all end the
    // session through the view model; the setter only runs on a system
    // dismissal, which ends both stages
    private var editorFlowPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isPhotoEditPresented || viewModel.isEditorPresented },
            set: { isPresented in
                if !isPresented {
                    viewModel.endPhotoEdit()
                    viewModel.endDiaryPrompt()
                }
            }
        )
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
            // v4 F9: the film viewfinder sits exactly over the preview layer
            // and ignores touches, so every gesture below still lands on the
            // layer's geometry. Off shows the plain layer.
            .overlay {
                if viewModel.showsFilmPreview {
                    FilmViewfinder(renderer: viewModel.filmPreviewRenderer)
                        .allowsHitTesting(false)
                }
            }
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
            switch viewModel.mode {
            case .photo:
                await viewModel.captureForPhoto()
            case .photobooth:
                if let shot = await viewModel.captureForPhotobooth() {
                    photobooth.add(shot)
                }
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

private struct FilmViewfinder: UIViewRepresentable {
    let renderer: FilmPreviewRenderer

    func makeUIView(context: Context) -> FilmPreviewView {
        FilmPreviewView(renderer: renderer)
    }

    func updateUIView(_ uiView: FilmPreviewView, context: Context) {}
}

#if DEBUG
// Compiled out of release. Launched with `-UITestPhotoEdit`, the camera opens the v5 F4 edit step on
// a generated photo (no camera) whose Download writes nowhere. Save to roll
// really saves, so a UI test can follow a photo into the Library Roll.
private enum PhotoEditFixture {
    static let launchArgument = "-UITestPhotoEdit"
    static let stock = StripCustomization.FilmStock.portrait400

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static let size = CGSize(width: 900, height: 1200)

    static func open(in camera: CameraViewModel) {
        camera.beginPhotoEdit(preview: photo(), stock: stock, savePhotoData: { _ in })
    }

    // A warm-to-cool diagonal gradient, so a film look visibly changes it
    static func photo() -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemTeal.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }
}
#endif

