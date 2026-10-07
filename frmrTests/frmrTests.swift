import ImageIO
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// In-memory SwiftData store: proves the schema and save/fetch/delete paths
// work without touching the app's real store
struct PersistenceTests {

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DiaryEntry.self, DailyStrip.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    @Test func diaryEntryRoundTrips() throws {
        let context = try makeContext()
        let entry = DiaryEntry(
            photoPath: "Photos/test.jpg",
            prompt: "What made you take this picture?",
            response: "The light."
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DiaryEntry>())

        #expect(fetched.count == 1)
        #expect(fetched[0].id == entry.id)
        #expect(fetched[0].photoPath == "Photos/test.jpg")
        #expect(fetched[0].prompt == "What made you take this picture?")
        #expect(fetched[0].response == "The light.")
    }

    @Test func dailyStripRoundTripsOrderedEntryIDs() throws {
        let context = try makeContext()
        let ids = [UUID(), UUID(), UUID(), UUID()]
        context.insert(DailyStrip(entryIDs: ids, isPhotobooth: false))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DailyStrip>())

        #expect(fetched.count == 1)
        #expect(fetched[0].entryIDs == ids)
        #expect(fetched[0].isPhotobooth == false)
        #expect(fetched[0].imageRelativePath == "Strips/\(fetched[0].id.uuidString).png")
    }

    @Test func deleteAllClearsBothModels() throws {
        // The path Settings' "Clear diary" relies on
        let context = try makeContext()
        context.insert(DiaryEntry(photoPath: "Photos/a.jpg", prompt: "P", response: "R"))
        context.insert(DailyStrip(entryIDs: [], isPhotobooth: true))
        try context.save()

        try context.delete(model: DiaryEntry.self)
        try context.delete(model: DailyStrip.self)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DiaryEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyStrip>()).isEmpty)
    }

    @Test func entriesSortNewestFirstLikeTheLibraryQuery() throws {
        let context = try makeContext()
        let older = DiaryEntry(createdAt: .now.addingTimeInterval(-3600), photoPath: "Photos/old.jpg", prompt: "P", response: "old")
        let newer = DiaryEntry(createdAt: .now, photoPath: "Photos/new.jpg", prompt: "P", response: "new")
        context.insert(older)
        context.insert(newer)
        try context.save()

        let descriptor = FetchDescriptor<DiaryEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let fetched = try context.fetch(descriptor)

        #expect(fetched.map(\.response) == ["new", "old"])
    }
}

struct StripGeneratorTests {

    private func makeCells(_ count: Int) -> [StripGenerator.Cell] {
        (0..<count).map { StripGenerator.Cell(image: nil, caption: "caption \($0)") }
    }

    @Test func fourEntriesMakeOneFullStrip() {
        let strips = StripGenerator.chunked(makeCells(4), paddingWith: .empty)

        #expect(strips.count == 1)
        #expect(strips[0].count == Constants.entriesPerStrip)
        #expect(strips[0].allSatisfy { !$0.caption.isEmpty })
    }

    @Test func fiveEntriesMakeTwoStripsSecondPaddedWithThreeEmptyCells() {
        let strips = StripGenerator.chunked(makeCells(5), paddingWith: .empty)

        #expect(strips.count == 2)
        #expect(strips[1].count == Constants.entriesPerStrip)
        #expect(strips[1][0].caption == "caption 4")

        let emptyCells = strips[1].filter { $0.caption.isEmpty && $0.image == nil }
        #expect(emptyCells.count == 3)
    }

    @Test func zeroEntriesMakeNoStrips() {
        let strips = StripGenerator.chunked(makeCells(0), paddingWith: .empty)

        #expect(strips.isEmpty)
    }

    @Test func renderedStripHasSpecWidth() {
        let image = StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: .now
        )

        #expect(image.size.width == Constants.Strip.width)
        #expect(image.size.height > 0)
        #expect(image.scale == Constants.Strip.renderScale)
    }

    // MARK: v2 F7 — film-edge detailing
    //
    // These mirror the layout arithmetic in StripGenerator.Layout, which is
    // private. If the layout moves, these fail — that's the point.

    private enum EdgeGeometry {
        typealias S = Constants.Strip
        static let inset = S.paperBorder + S.contentPadding
        static let cellWidth = S.width - inset * 2
        static let photoHeight = cellWidth / S.cellAspectRatio
        static let scale = S.renderScale

        /// Centre of the first sprocket hole in the left column, in pixels.
        static var firstLeftHole: (x: Int, y: Int) {
            let band = photoHeight / CGFloat(S.sprocketHoleCount)
            return (Int(S.sprocketHoleInset * scale), Int((inset + band * 0.5) * scale))
        }

        static var firstRightHole: (x: Int, y: Int) {
            (Int((S.width - S.sprocketHoleInset) * scale), firstLeftHole.y)
        }

        /// The reserved gutter where frame number "01" is drawn, in pixels.
        static var firstFrameNumberRect: (x: Range<Int>, y: Range<Int>) {
            let columnWidth = ceil(S.frameNumberFontSize * 2.4)
            let originX = inset + cellWidth - columnWidth
            let originY = inset + photoHeight + S.captionSpacing + S.frameNumberInset
            let height = ceil(S.frameNumberFontSize * 1.4)
            return (
                Int(originX * scale)..<Int((originX + columnWidth) * scale),
                Int(originY * scale)..<Int((originY + height) * scale)
            )
        }
    }

    private func renderedStrip() -> UIImage {
        StripGenerator.render(
            strip: Array(repeating: .empty, count: Constants.entriesPerStrip),
            customization: StripCustomization(),
            date: .now
        )
    }

    @Test func sprocketHolesArePunchedIntoBothPaperBorders() throws {
        let buffer = try #require(PixelBuffer(renderedStrip()))

        for hole in [EdgeGeometry.firstLeftHole, EdgeGeometry.firstRightHole] {
            let x = min(hole.x, buffer.width - 1)
            let pixel = buffer.rgb(x: x, y: hole.y)
            // The paper is white; a punched hole is near-black (#001219)
            #expect(pixel.r < 60 && pixel.g < 60 && pixel.b < 60, "no hole at \(hole)")
        }
    }

    @Test func paperBorderStaysWhiteBetweenSprocketHoles() throws {
        // Guards against the holes being drawn as a solid bar
        let buffer = try #require(PixelBuffer(renderedStrip()))
        let topOfBorder = 1
        let pixel = buffer.rgb(x: Int(Constants.Strip.sprocketHoleInset * Constants.Strip.renderScale), y: topOfBorder)

        #expect(pixel.r > 200 && pixel.g > 200 && pixel.b > 200)
    }

    @Test func frameNumbersArePrintedInAmberInTheReservedGutter() throws {
        let buffer = try #require(PixelBuffer(renderedStrip()))
        let rect = EdgeGeometry.firstFrameNumberRect

        // Amber (#EE9B00) on cream: look for pixels clearly warmer than the paper
        let amberPixels = rect.y.flatMap { y in
            rect.x.compactMap { x -> Bool? in
                guard x < buffer.width, y < buffer.height else { return nil }
                let pixel = buffer.rgb(x: x, y: y)
                return pixel.r - pixel.b > 120 ? true : nil
            }
        }

        #expect(!amberPixels.isEmpty, "frame number '01' not found in its gutter")
    }
}

// MARK: - v2 helpers

// Minimal RGBA pixel reader so the rendering tests can assert on real output
// rather than on the code that produced it.
private struct PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        width = cgImage.width
        height = cgImage.height

        var raw = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = raw
    }

    func rgb(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let offset = (y * width + x) * 4
        return (Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]))
    }

    /// Variance of per-pixel luminance — how much grain is present.
    var luminanceVariance: Double {
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                values.append(0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    var channelMeans: (r: Double, g: Double, b: Double) {
        var totals = (r: 0.0, g: 0.0, b: 0.0)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = rgb(x: x, y: y)
                totals.r += pixel.r
                totals.g += pixel.g
                totals.b += pixel.b
            }
        }
        let count = Double(width * height)
        return (totals.r / count, totals.g / count, totals.b / count)
    }
}

private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - v2 F4 / F5: grain and film stocks

struct ImageProcessorTests {

    private func variance(of stock: StripCustomization.FilmStock, on color: UIColor) throws -> Double {
        var customization = StripCustomization()
        customization.filmStock = stock
        let output = ImageProcessor.applyStripLook(to: solidImage(color), customization: customization)
        let buffer = try #require(PixelBuffer(output))
        return buffer.luminanceVariance
    }

    @Test func grainIsHeavierInShadowsThanMidtones() throws {
        // The U-curve over luminance is what separates film grain from a flat
        // noise overlay (v2 F4): shadows get ~1.0 weight, midtones ~0.3.
        let shadowVariance = try variance(of: .iso3200, on: .black)
        let midtoneVariance = try variance(of: .iso3200, on: UIColor(white: 0.5, alpha: 1))

        #expect(shadowVariance > midtoneVariance)
    }

    @Test func heavierStockProducesMoreGrainThanFinerStock() throws {
        let fine = try variance(of: .iso100, on: .black)
        let heavy = try variance(of: .iso3200, on: .black)

        #expect(heavy > fine)
    }

    @Test func filmStockNoneLeavesTheImageUntouched() throws {
        var customization = StripCustomization()
        customization.filmStock = .none
        let input = solidImage(UIColor(white: 0.5, alpha: 1))
        let output = ImageProcessor.applyStripLook(to: input, customization: customization)

        #expect(output === input)
    }

    @Test func warmStocksPushRedAboveBlueAndNeutralStocksDoNot() throws {
        let grey = UIColor(white: 0.5, alpha: 1)

        for stock in [StripCustomization.FilmStock.iso400, .iso3200] {
            var customization = StripCustomization()
            customization.filmStock = stock
            let buffer = try #require(
                PixelBuffer(ImageProcessor.applyStripLook(to: solidImage(grey), customization: customization))
            )
            let means = buffer.channelMeans
            #expect(means.r > means.b, "\(stock.label) should read warm")
        }

        var neutral = StripCustomization()
        neutral.filmStock = .iso100
        let buffer = try #require(
            PixelBuffer(ImageProcessor.applyStripLook(to: solidImage(grey), customization: neutral))
        )
        let means = buffer.channelMeans
        #expect(abs(means.r - means.b) < 2, "ISO 100 carries no colour cast")
    }

    // A landscape- or diagonally-held capture is recorded as an EXIF tag, so
    // this mapping is what decides whether the developed RAW reads upright.
    // The two enums share case names but not raw values — bridging through
    // rawValue would silently turn .right into .downMirrored.
    @Test func exifOrientationMapsOntoTheMatchingUIImageOrientation() {
        let expected: [(CGImagePropertyOrientation, UIImage.Orientation)] = [
            (.up, .up),
            (.upMirrored, .upMirrored),
            (.down, .down),
            (.downMirrored, .downMirrored),
            (.leftMirrored, .leftMirrored),
            (.right, .right),
            (.rightMirrored, .rightMirrored),
            (.left, .left),
        ]
        for (exif, ui) in expected {
            #expect(ImageProcessor.uiOrientation(from: exif) == ui)
        }
    }

    // The four upright quarter-turns must stay distinct: collapsing any two
    // is what a sign-convention slip looks like, and it would rotate every
    // landscape capture the wrong way rather than failing loudly.
    @Test func theFourQuarterTurnsAreDistinct() {
        let quarterTurns: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let mapped = quarterTurns.map(ImageProcessor.uiOrientation(from:))
        #expect(Set(mapped.map(\.rawValue)).count == quarterTurns.count)
    }

    @Test func liveGrainTileShiftsBetweenFrames() throws {
        // v2 F6: a tile that doesn't move between frames reads as a filter
        let size = CGSize(width: 32, height: 32)
        let first = try #require(ImageProcessor.makeLiveGrainTile(size: size, phase: 0))
        let second = try #require(ImageProcessor.makeLiveGrainTile(size: size, phase: 37))

        let a = try #require(PixelBuffer(UIImage(cgImage: first)))
        let b = try #require(PixelBuffer(UIImage(cgImage: second)))
        let differs = (0..<size.height.intValue).contains { y in
            (0..<size.width.intValue).contains { x in a.rgb(x: x, y: y) != b.rgb(x: x, y: y) }
        }

        #expect(differs)
    }
}

private extension CGFloat {
    var intValue: Int { Int(self) }
}

// MARK: - v2 F5: film stock migration

struct FilmStockMigrationTests {

    @Test func legacyGrainToggleMapsOntoTheClosestStock() {
        #expect(StripCustomization.FilmStock.migrating(fromLegacyGrainEnabled: false) == .none)
        #expect(StripCustomization.FilmStock.migrating(fromLegacyGrainEnabled: true) == .iso400)
    }

    @Test func everyStockExceptNoneHasAProfile() {
        for stock in StripCustomization.FilmStock.allCases {
            #expect((stock.profile == nil) == (stock == .none))
        }
    }
}

// MARK: - v2 F2 / F3: gesture mapping

@MainActor
struct CameraControlMappingTests {

    @Test func draggingUpBrightensAndDraggingDownDarkens() {
        // Negative translation.height is upward: swipe up = more light
        let brighter = CameraViewModel.exposureBias(fromDragHeight: -Constants.Camera.exposureDragScale, base: 0)
        let darker = CameraViewModel.exposureBias(fromDragHeight: Constants.Camera.exposureDragScale, base: 0)

        #expect(brighter == 1.0)
        #expect(darker == -1.0)
    }

    @Test func exposureBiasClampsToTheConfiguredRange() {
        let farUp = CameraViewModel.exposureBias(fromDragHeight: -10_000, base: 0)
        let farDown = CameraViewModel.exposureBias(fromDragHeight: 10_000, base: 0)

        #expect(farUp == Constants.Camera.exposureBiasMax)
        #expect(farDown == Constants.Camera.exposureBiasMin)
    }

    @Test func exposureDragAccumulatesFromTheBiasAtDragStart() {
        let result = CameraViewModel.exposureBias(
            fromDragHeight: -Constants.Camera.exposureDragScale / 2,
            base: 0.5
        )

        #expect(result == 1.0)
    }

    @Test func zoomClampsToTheDeviceRange() {
        #expect(CaptureSession.clampedZoom(5, min: 1, max: 10) == 5)
        #expect(CaptureSession.clampedZoom(50, min: 1, max: 10) == 10)
        #expect(CaptureSession.clampedZoom(0.2, min: 1, max: 10) == 1)
    }

    @Test func zoomCollapsesToTheMinimumWhenTheCameraCannotZoom() {
        // Front cameras commonly report min == max
        #expect(CaptureSession.clampedZoom(4, min: 1, max: 1) == 1)
    }

    @Test func chromeCounterRotatesToTheFourCardinalOrientations() {
        #expect(CameraViewModel.rotationAngle(for: .portrait, current: .degrees(90)) == .zero)
        #expect(CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: .zero) == .degrees(180))
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .zero) == .degrees(90))
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .zero) == .degrees(-90))
    }

    @Test func chromeRotationTakesTheShortArcBetweenLandscapes() {
        let a = CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(90))
        #expect(abs(a.degrees - 90) == 180)
        // 270 is the same pose as -90: no animation
        #expect(CameraViewModel.rotationAngle(for: .landscapeRight, current: .degrees(270)) == .degrees(270))
    }

    @Test func chromeRotationAccumulatesWithoutWrapping() {
        var angle = Angle.zero
        angle = CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: angle)
        #expect(angle.degrees == 180)
        angle = CameraViewModel.rotationAngle(for: .landscapeLeft, current: angle)
        #expect(angle.degrees == 90)   // 180 -> 90, delta -90
        angle = CameraViewModel.rotationAngle(for: .portrait, current: angle)
        #expect(angle.degrees == 0)
    }

    @Test func chromeRotationEveryStepIsAtMost180() {
        let all: [UIDeviceOrientation] = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
        for from in all {
            for to in all {
                let start = CameraViewModel.rotationAngle(for: from, current: .zero)
                let end = CameraViewModel.rotationAngle(for: to, current: start)
                #expect(abs(end.degrees - start.degrees) <= 180)
            }
        }
    }

    @Test func chromeRotationDoesNotDriftOnRepeatedOrientation() {
        var angle = Angle.zero
        for _ in 0..<10 {
            angle = CameraViewModel.rotationAngle(for: .portraitUpsideDown, current: angle)
            angle = CameraViewModel.rotationAngle(for: .portrait, current: angle)
        }
        // Tie direction is consistent (+180 each way), so it accumulates in
        // whole turns but never drifts off a cardinal pose
        #expect(angle.degrees.truncatingRemainder(dividingBy: 360) == 0)
        let held = CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(90))
        #expect(held == .degrees(90))
    }

    @Test func chromeRotationHoldsLastKnownAngleOnFaceUpOrDown() {
        let held = Angle.degrees(-90)
        #expect(CameraViewModel.rotationAngle(for: .faceUp, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .faceDown, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .unknown, current: held) == held)
        #expect(CameraViewModel.rotationAngle(for: .landscapeLeft, current: .degrees(720)) == .degrees(810))
    }
}

// MARK: - v3 F3: collapsible white balance

struct WhiteBalanceVisibilityTests {

    @Test func everyWhiteBalanceModeHasASymbolName() {
        for mode in WBMode.allCases { #expect(!mode.symbolName.isEmpty) }
    }

    @Test func collapsedShowsExactlyTheSelectedMode() {
        for mode in WBMode.allCases {
            #expect(CameraViewModel.visibleModes(expanded: false, selected: mode) == [mode])
        }
    }

    @Test func expandedShowsAllModesInDeclarationOrder() {
        #expect(CameraViewModel.visibleModes(expanded: true, selected: .cloudy) == WBMode.allCases)
    }

    @Test func selectedModeIsPresentInBothStates() {
        for mode in WBMode.allCases {
            #expect(CameraViewModel.visibleModes(expanded: false, selected: mode).contains(mode))
            #expect(CameraViewModel.visibleModes(expanded: true, selected: mode).contains(mode))
        }
    }
}

// MARK: - v3 F5/F6: first-run walkthrough

struct OnboardingSequencingTests {

    // A fresh view model with the walkthrough running from step one; never
    // started against a ModelContext, so persistence is inert in these tests
    private func runningViewModel() -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.reset()
        return viewModel
    }

    @Test func advancingThroughAllThreeStepsCompletesExactlyOnce() {
        let viewModel = runningViewModel()
        #expect(viewModel.step == .library)
        viewModel.advance()
        #expect(viewModel.step == .camera)
        viewModel.advance()
        #expect(viewModel.step == .settings)
        #expect(!viewModel.hasCompleted)
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
        // Advancing past the end must not re-complete or revive a step
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
    }

    @Test func skipCompletesImmediatelyFromEveryStep() {
        for step in CoachStep.allCases {
            let viewModel = runningViewModel()
            for _ in 0..<step.rawValue { viewModel.advance() }
            #expect(viewModel.step == step)
            viewModel.skip()
            #expect(viewModel.step == nil)
            #expect(viewModel.hasCompleted)
        }
    }

    @Test func resetReturnsToTheFirstStepAndClearsCompletion() {
        let viewModel = runningViewModel()
        viewModel.skip()
        viewModel.reset()
        #expect(viewModel.step == .library)
        #expect(!viewModel.hasCompleted)
    }

    @Test func shouldPresentRequiresAllThreeGates() {
        #expect(OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: true, permissionResolved: true, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: false, isPortrait: true))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: false))
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: false, permissionResolved: true, isPortrait: false))
    }

    @Test func onboardingPortraitGateHoldsOnFlatOrientations() {
        #expect(OnboardingViewModel.isPortrait(for: .portraitUpsideDown, current: false))
        #expect(!OnboardingViewModel.isPortrait(for: .landscapeLeft, current: true))
        #expect(!OnboardingViewModel.isPortrait(for: .landscapeRight, current: true))
        #expect(!OnboardingViewModel.isPortrait(for: .faceUp, current: false))
        #expect(OnboardingViewModel.isPortrait(for: .unknown, current: true))
    }

    @Test func stepOrderIsLibraryCameraSettings() {
        #expect(CoachStep.library.next == .camera)
        #expect(CoachStep.camera.next == .settings)
        #expect(CoachStep.settings.next == nil)
    }

    // Completion must survive a relaunch: a second view model loading from
    // the same store starts completed, and replay clears it again (F6)
    @Test func completionPersistsAcrossViewModelLifetimes() throws {
        let container = try ModelContainer(
            for: OnboardingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = OnboardingViewModel()
        first.start(context: context)
        first.reset()
        first.skip()
        #expect(first.hasCompleted)

        let relaunched = OnboardingViewModel()
        relaunched.start(context: context)
        #expect(relaunched.hasCompleted)
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: relaunched.hasCompleted, permissionResolved: true, isPortrait: true))

        relaunched.replayWalkthrough()
        #expect(relaunched.step == .library)
        #expect(relaunched.selectedTab == .camera)

        let afterReplay = OnboardingViewModel()
        afterReplay.start(context: context)
        #expect(!afterReplay.hasCompleted)
    }

    // Catches a step being added without copy
    @Test func everyStepHasCopy() {
        for step in CoachStep.allCases {
            let entry = CoachCopy.entries[step]
            #expect(entry != nil)
            #expect(entry?.title.isEmpty == false)
            #expect(entry?.body.isEmpty == false)
        }
    }
}

// MARK: - v2 F8b: typewriter

struct TypewriterTextTests {

    @Test func revealsEveryCharacterInOrder() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("hello", interval: 0.001) { frames.append($0) }

        #expect(frames == ["h", "he", "hel", "hell", "hello"])
    }

    @Test func emptyTextProducesNoFrames() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("", interval: 0.001) { frames.append($0) }

        #expect(frames.isEmpty)
    }
}

struct PromptSelectionTests {

    @Test func neverRepeatsThePreviousPromptImmediately() {
        var last: Int? = nil
        for _ in 0..<500 {
            let next = DiaryViewModel.nextPromptIndex(excluding: last, count: PromptBank.all.count)
            #expect(next != last)
            #expect((0..<PromptBank.all.count).contains(next))
            last = next
        }
    }

    @Test func singlePromptBankAlwaysReturnsTheOnlyIndex() {
        let index = DiaryViewModel.nextPromptIndex(excluding: 0, count: 1)

        #expect(index == 0)
    }

    @Test func promptBankMeetsMinimumSize() {
        // project.md §11 requires at least 50 prompts
        #expect(PromptBank.all.count >= 50)
    }
}
