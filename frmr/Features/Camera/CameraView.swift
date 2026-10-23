import AVFoundation
import SwiftData
import SwiftUI
import TipKit

// The camera (v5 F1, v5.1 F8/F9, v5.2 S1/S2). Where there is room — a 3:4
// viewfinder plus the dial and shutter fit under the safe area — the dial
// and shutter sit on black BELOW the picture; on short phones they float
// over its bottom on glass (`CameraViewModel.chromePlacement`). The mode
// switch, WB and EV float over the picture's top either way. Photo and Film
// strip share every piece: Film strip only swaps the last-photo thumbnail
// for the mini-strip.
struct CameraView: View {
    @Environment(ErrorState.self) private var errorState
    @AppStorage(Constants.DefaultsKeys.cameraGrid) private var cameraGrid = CameraGrid.off.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CameraViewModel()
    @State private var photobooth = PhotoboothViewModel()
    @State private var hudFlash: CameraHUDFlash?
    @State private var isSlotsSheetPresented = false
    // Generate closes the slots sheet first; the strip opens once it is gone
    @State private var generatesAfterSheet = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let dialTip = DialTip()
    private let shutterTip = ShutterTip()
    private let modeTip = ModeTip()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ThemePalette.letterbox.ignoresSafeArea()

                // DELIBERATE TEMPORARY SAFETY NET: under the portrait lock this
                // branch never runs. Remove it (and dockedChrome) once the lock is
                // verified on a physical device.
                // Compact height means the interface itself is landscape (only
                // possible if the portrait lock did not hold, or is lifted by
                // decision). The system has already turned the screen, so the
                // counter-rotation is zeroed there or glyphs would turn twice.
                if verticalSizeClass == .compact {
                    viewfinder.ignoresSafeArea()
                    dockedChrome
                        .environment(\.deviceRotation, .zero)
                } else {
                    portraitLayout(placement: placement(for: proxy))
                }

                PermissionDeniedOverlay(isVisible: viewModel.isPermissionDenied)

                chromeDebugOverlay
            }
        }
        // BUG-521-04: the camera stays alive under the prompt's cover, and the
        // keyboard's inset reached this proxy. It flipped the placement from
        // .below to .overlay, which rebuilt CameraPreview; re-attaching the
        // running session on the main thread hung the app until the watchdog
        // killed it (0x8BADF00D). The camera never makes room for a keyboard.
        .ignoresSafeArea(.keyboard)
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
        }
        .onDisappear {
            viewModel.stopCamera()
        }
        // v5.2 S1: changed values flash in the viewfinder
        .onChange(of: viewModel.filmStock) { _, stock in
            dialTip.invalidate(reason: .actionPerformed)
            flash(stock.label)
        }
        .onChange(of: viewModel.selectedLens) { _, lens in flash(lens.label) }
        .onChange(of: viewModel.exposureBias) { _, _ in flash(viewModel.exposureReadout + " EV") }
        .task {
            // The shutter tip waits until the dial tip is done with
            for await status in dialTip.statusUpdates {
                if case .invalidated = status { ShutterTip.isDialTipDone = true }
            }
        }
        // v5.1 F8: white balance and exposure open as glass sheets
        .sheet(isPresented: controlSheetPresented) {
            CameraControlSheet(viewModel: viewModel)
        }
        // v5.2 S2: the mini-strip opens the strip's slots and actions
        .sheet(isPresented: $isSlotsSheetPresented, onDismiss: openGeneratedStrip) {
            StripSlotsSheet(viewModel: photobooth, onGenerate: generateStrip)
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

    // The full screen including safe areas, and the insets (the bottom one
    // includes the tab bar), as CameraViewModel.chromePlacement expects
    private func placement(for proxy: GeometryProxy) -> ChromePlacement {
        let insets = proxy.safeAreaInsets
        let size = CGSize(
            width: proxy.size.width + insets.leading + insets.trailing,
            height: proxy.size.height + insets.top + insets.bottom
        )
        return CameraViewModel.chromePlacement(for: size, safeArea: insets)
    }

    // Portrait positions are the only positions. In landscape each control
    // turns about its own centre (rotatingWithDevice) and nothing moves,
    // stacks or reflows.
    @ViewBuilder
    private func portraitLayout(placement: ChromePlacement) -> some View {
        switch placement {
        case .below:
            VStack(spacing: 0) {
                viewfinder
                    .aspectRatio(Constants.CameraUI.viewfinderAspect, contentMode: .fit)
                    .overlay(alignment: .top) { topBar }
                    .overlay(alignment: .bottom) {
                        lensChips.padding(.bottom, Constants.DesignUI.Space.m)
                    }
                    .overlay(alignment: .top) { hud }
                    .padding(.top, Constants.Camera.belowChromeTopMargin)
                Spacer(minLength: 0)
                bottomStack
                Spacer(minLength: 0)
            }
        case .overlay:
            viewfinder
                .ignoresSafeArea()
                .overlay(alignment: .top) { hud.padding(.top, Constants.CameraUI.hudOverlayTopPadding) }
            VStack(spacing: Constants.CameraUI.bottomStackSpacing) {
                topBar
                Spacer()
                lensChips
                bottomStack
            }
        }
    }

    private var hud: some View {
        CameraHUD(flash: hudFlash)
            .frame(maxWidth: .infinity)
            .padding(.top, Constants.CameraUI.hudTopPadding)
    }

    @ViewBuilder private var lensChips: some View {
        if viewModel.isLensSelectorVisible {
            LensChipRow(
                lenses: viewModel.availableLenses,
                selected: viewModel.selectedLens,
                onSelect: viewModel.selectLens
            )
        }
    }

    // Dial, then the shutter row: last photo or mini-strip, shutter, flip.
    // A circle looks identical at any angle, so the shutter never rotates.
    private var bottomStack: some View {
        VStack(spacing: Constants.CameraUI.bottomStackSpacing) {
            StockDial(selected: viewModel.filmStock, onSelect: viewModel.selectFilmStock)
                .popoverTip(dialTip, arrowEdge: .bottom)
                .padding(.horizontal, Constants.CameraUI.screenMargin)

            ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                .popoverTip(shutterTip, arrowEdge: .bottom)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { leadingAccessory }
                .overlay(alignment: .trailing) {
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                        .padding(.trailing, Constants.CameraUI.screenMargin)
                }
                .padding(.bottom, Constants.CameraUI.shutterBottomPadding)
        }
    }

    // Mode switch at the top left, WB and EV at the top right (v5.1-9)
    private var topBar: some View {
        HStack {
            ModeSwitch(selected: viewModel.mode, onSelect: selectMode)
                .popoverTip(modeTip, arrowEdge: .top)
            Spacer()
            controlButtons
        }
        .padding(.horizontal, Constants.CameraUI.screenMargin)
        .padding(.top, Constants.CameraUI.topBarTopPadding)
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

    // Photo: the newest Roll photo. Film strip: the mini-strip in the same
    // place (v5.2 S2), so the two modes' chrome is identical.
    @ViewBuilder private var leadingAccessory: some View {
        Group {
            if viewModel.isPhotoMode {
                LastPhotoButton()
            } else {
                MiniStripButton(viewModel: photobooth) { isSlotsSheetPresented = true }
            }
        }
        .padding(.leading, Constants.CameraUI.screenMargin)
    }

    // The panel slot is shared, so leaving a mode closes whatever was open
    private func selectMode(_ mode: CameraViewModel.Mode) {
        viewModel.closePanels()
        switch mode {
        case .photo: viewModel.selectPhotoMode()
        case .photobooth:
            modeTip.invalidate(reason: .actionPerformed)
            viewModel.selectPhotoboothMode()
        }
    }

    private func flash(_ text: String) {
        hudFlash = CameraHUDFlash(text: text)
    }

    private func generateStrip() {
        generatesAfterSheet = true
        isSlotsSheetPresented = false
    }

    private func openGeneratedStrip() {
        guard generatesAfterSheet else { return }
        generatesAfterSheet = false
        photobooth.isStripPresented = true
    }

    // Far-right dock, like the system Camera in landscape. Anchored with an
    // overlay on a non-rotating parent so nothing swings when the screen turns.
    private var dockedChrome: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                VStack(spacing: Constants.CameraUI.dockSpacing) {
                    ModeSwitch(selected: viewModel.mode, onSelect: selectMode)
                    lensChips
                    controlButtons
                    ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                    leadingAccessory
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                }
                .padding(.trailing, Constants.CameraUI.dockTrailingPadding)
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
                .frmrCodeStyle()
                .foregroundStyle(.yellow)
                .padding(Constants.DesignUI.Space.xs)
                .background(.black)
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
            .frmrAnimation(.panel, value: viewModel.isExposureIndicatorVisible)
            .contentShape(Rectangle())
            .gesture(exposureDrag)
            .gesture(pinchZoom)
            .onTapGesture(count: 2) { viewModel.resetZoom() }
            .onTapGesture { location in viewModel.userTapped(at: location) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Viewfinder")
            .accessibilityHint("Tap to focus. Swipe up or down to change exposure.")
            .accessibilityIdentifier("camera.viewfinder")
            // F-GRID: inside the frame, after the viewfinder's single
            // accessibility element so the lines stay out of VoiceOver
            .overlay(ViewfinderGridOverlay(grid: CameraGrid(rawValue: cameraGrid) ?? .off))
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
        shutterTip.invalidate(reason: .actionPerformed)
        Task {
            switch viewModel.mode {
            case .photo:
                await viewModel.captureForPhoto(context: modelContext)
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

