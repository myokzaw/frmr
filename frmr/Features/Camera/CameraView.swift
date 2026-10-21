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
            // UI tests only: the simulator has no camera, so the review
            // screen is reached through a fixture capture instead
            if DiaryReviewFixture.isRequested {
                DiaryReviewFixture.open(in: viewModel)
                return
            }
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
        // One cover for the whole diary flow (v4 F10): review, then the
        // prompt screen. Two covers would have to dismiss one and present
        // the other in the same update when OK is tapped.
        .fullScreenCover(isPresented: diaryFlowPresented) {
            DiaryFlowView(camera: viewModel)
        }
        // v5 F4: the Photo-mode edit step
        .fullScreenCover(isPresented: photoEditPresented) {
            if let edit = viewModel.photoEdit {
                PhotoEditView(edit: edit)
            }
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
            modeToggle
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

                modeControls

                // A circle looks identical at any angle, so the shutter
                // itself never rotates.
                ZStack {
                    ShutterButton(isDisabled: viewModel.isShutterDisabled, action: shutterTapped)
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    if viewModel.isPhotoMode {
                        LastPhotoButton()
                            .padding(.leading, Constants.EditorUI.buttonPadding)
                    }
                }
                .overlay(alignment: .trailing) {
                    FlipCameraButton(isVisible: viewModel.isFlipCameraVisible, action: viewModel.flipCamera)
                        .padding(.trailing, Constants.EditorUI.buttonPadding)
                }
                .padding(.bottom, Constants.CameraUI.shutterBottomPadding)
            }
        }
    }

    private var modeToggle: some View {
        ModeToggle(selected: viewModel.mode, onSelect: selectMode)
    }

    // The panel slot is shared, so leaving a mode closes whatever was open
    private func selectMode(_ mode: CameraViewModel.Mode) {
        viewModel.closePanels()
        switch mode {
        case .photo: viewModel.selectPhotoMode()
        case .diary: viewModel.selectDiaryMode()
        case .photobooth: viewModel.selectPhotoboothMode()
        }
    }

    // Photo mode (v5 F2/F3): WB and EV chips with their panels, then the
    // stock dial. Diary and Film strip keep the v4 Film chip and WB bank
    // (OPEN: v5-2).
    @ViewBuilder private var modeControls: some View {
        if viewModel.isPhotoMode {
            photoControls
        } else {
            filmStockControl
            WhiteBalanceControl(
                selected: viewModel.whiteBalance,
                isExpanded: viewModel.isWhiteBalanceExpanded,
                onToggle: viewModel.toggleWhiteBalanceExpansion,
                onSelect: viewModel.selectWhiteBalance
            )
        }
    }

    private var photoControls: some View {
        VStack(spacing: Constants.CameraUI.chipSpacing) {
            if viewModel.isWhiteBalanceExpanded {
                WhiteBalancePanel(
                    activePreset: viewModel.activeWhiteBalancePreset,
                    kelvin: viewModel.whiteBalanceKelvin,
                    tint: viewModel.whiteBalanceTint,
                    onPreset: viewModel.chooseWhiteBalancePreset,
                    onKelvin: viewModel.setWhiteBalanceKelvin,
                    onTint: viewModel.setWhiteBalanceTint
                )
                .transition(.opacity)
            }
            if viewModel.isExposurePanelExpanded {
                ExposurePanel(
                    bias: viewModel.exposureBias,
                    readout: viewModel.exposureReadout,
                    onBias: viewModel.setExposureBias,
                    onStep: viewModel.stepExposureBias(by:)
                )
                .transition(.opacity)
            }
            PhotoControlChips(
                whiteBalanceText: viewModel.whiteBalanceChipText,
                exposureText: viewModel.exposureReadout,
                isWhiteBalanceOpen: viewModel.isWhiteBalanceExpanded,
                isExposureOpen: viewModel.isExposurePanelExpanded,
                onToggleWhiteBalance: viewModel.toggleWhiteBalanceExpansion,
                onToggleExposure: viewModel.toggleExposurePanel
            )
            StockDial(selected: viewModel.filmStock, onSelect: viewModel.selectFilmStock)
        }
        .animation(.easeInOut(duration: Constants.CameraUI.panelAnimationDuration), value: viewModel.openPanel)
    }

    // Far-right dock, like the system Camera in landscape. Anchored with an
    // overlay on a non-rotating parent so nothing swings when the screen turns.
    private var dockedChrome: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                VStack(spacing: Constants.CameraUI.dockSpacing) {
                    modeToggle
                    if viewModel.isLensSelectorVisible {
                        LensChipRow(
                            lenses: viewModel.availableLenses,
                            selected: viewModel.selectedLens,
                            onSelect: viewModel.selectLens
                        )
                    }
                    modeControls
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

    // v4 F9: shown in both Diary and Film strip modes
    private var filmStockControl: some View {
        FilmStockControl(
            selected: viewModel.filmStock,
            isExpanded: viewModel.isFilmStockExpanded,
            onToggle: viewModel.toggleFilmStockExpansion,
            onSelect: viewModel.selectFilmStock
        )
    }

    // Dismissing the cover (Retake, Save, Skip) goes through the view model,
    // which clears both flags; the setter only runs on a system dismissal
    private var diaryFlowPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isReviewPresented || viewModel.isEditorPresented },
            set: { isPresented in
                if !isPresented { viewModel.retake() }
            }
        )
    }

    // Retake, Discard and Save all end the edit session through the view
    // model; the setter only runs on a system dismissal
    private var photoEditPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isPhotoEditPresented },
            set: { isPresented in
                if !isPresented { viewModel.endPhotoEdit() }
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
            case .diary:
                await viewModel.captureForDiary()
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

// The diary flow's single full-screen cover: the review (v4 F10) until OK,
// then the prompt screen
private struct DiaryFlowView: View {
    let camera: CameraViewModel

    var body: some View {
        if camera.isEditorPresented {
            EntryEditorView(camera: camera)
        } else if let review = camera.review {
            DiaryReviewView(review: review, onConfirm: camera.confirmReview, onRetake: camera.retake)
        }
    }
}

// A static capsule holding three square icon segments (v5 F1): Photo, Diary,
// Film strip. The capsule never rotates — it is wider than tall — only the
// glyph inside each segment does.
private struct ModeToggle: View {
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
        .padding(Constants.CameraUI.modePillPadding)
        .background(.white.opacity(Constants.CameraUI.chipInactiveOpacity), in: Capsule())
    }
}

private extension CameraViewModel.Mode {
    var symbolName: String {
        switch self {
        case .photo: return "camera"
        case .diary: return "book.closed"
        case .photobooth: return "film"
        }
    }

    var identifierName: String {
        switch self {
        case .photo: return "photo"
        case .diary: return "diary"
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
        .accessibilityIdentifier(identifier)
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

// v5: the newest Roll photo, at the shutter's left. Tapping opens that
// photo's editor (re-edit mode) right here, so the next shot is one Save
// away; the whole Roll is in the Library. Hidden, but still taking its
// space, while the Roll is empty. The square keeps its shape in landscape:
// only the picture inside turns, so it reads upright.
private struct LastPhotoButton: View {
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

#if DEBUG
// Compiled out of release. Launched with `-UITestDiaryReview`, the camera
// opens the v4 F10 review on a generated photo (no camera, no files) whose
// Download writes nowhere, so a UI test can drive review → OK → prompt
// without touching the photo library.
private enum DiaryReviewFixture {
    static let launchArgument = "-UITestDiaryReview"
    static let stock = StripCustomization.FilmStock.portrait400
    static let size = CGSize(width: 900, height: 1200)

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func open(in camera: CameraViewModel) {
        camera.beginReview(preview: photo(), stock: stock, savePhotoData: { _ in })
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

// Launched with `-UITestPhotoEdit`, the camera opens the v5 F4 edit step on
// a generated photo (no camera) whose Download writes nowhere. Save to roll
// really saves, so a UI test can follow a photo into the Library Roll.
private enum PhotoEditFixture {
    static let launchArgument = "-UITestPhotoEdit"
    static let stock = StripCustomization.FilmStock.portrait400

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func open(in camera: CameraViewModel) {
        camera.beginPhotoEdit(preview: DiaryReviewFixture.photo(), stock: stock, savePhotoData: { _ in })
    }
}
#endif

