import Foundation
import Testing
@testable import frmr

// BUG-122-01 / BUG-122-02: the flip state machine. The session and the frame
// sink are swapped for stubs; the real ones need a camera.

@MainActor
struct CameraSwitchTests {
    /// A frame wait the test releases by hand.
    private final class Gate: @unchecked Sendable {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false
        // Sticky, so opening before the wait begins still releases it
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() { isOpen = true; continuation?.resume(); continuation = nil }
    }

    private func makeCamera(attaches: Bool = true, gate: Gate = Gate(), timeout: Duration = .seconds(5)) throws -> CameraViewModel {
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        camera.switchOperation = { _, _ in attaches }
        camera.awaitNewFrame = { await gate.wait() }
        camera.cancelFrameWait = { gate.open() }
        camera.switchTimeout = timeout
        return camera
    }

    private func settle(_ camera: CameraViewModel) async {
        await camera.switchSettled()
    }

    @Test func flipShowsTheTransitionUntilTheFirstNewFrame() async throws {
        let gate = Gate()
        let camera = try makeCamera(gate: gate)

        camera.flipCamera()
        #expect(camera.isSwitchingCamera)
        #expect(camera.flipTransition != nil)
        #expect(camera.cameraPosition == .front)

        for _ in 0..<5 { await Task.yield() }
        #expect(camera.isSwitchingCamera, "still waiting for a frame")

        gate.open()
        await settle(camera)
        #expect(!camera.isSwitchingCamera)
        #expect(camera.flipTransition == nil)
        #expect(camera.cameraPosition == .front)
    }

    @Test func flipTapsAreIgnoredWhileSwitching() async throws {
        let gate = Gate()
        let camera = try makeCamera(gate: gate)

        camera.flipCamera()
        camera.flipCamera()
        camera.flipCamera()
        #expect(camera.cameraPosition == .front, "a second tap must not flip back")
        camera.selectLens(.ultraWide)
        #expect(camera.selectedLens == .wide, "lens taps are ignored too")

        gate.open()
        await settle(camera)
        camera.flipCamera()
        #expect(camera.cameraPosition == .back, "taps work again after the switch")
        gate.open()
        await settle(camera)
    }

    @Test func aFailedSwitchKeepsTheOldCameraAndClearsTheTransition() async throws {
        let camera = try makeCamera(attaches: false)
        let errors = ErrorState()
        camera.errorState = errors

        camera.flipCamera()
        await settle(camera)

        #expect(camera.cameraPosition == .back)
        #expect(!camera.isSwitchingCamera)
        #expect(camera.flipTransition == nil)
        #expect(errors.current != nil, "the failure reaches the user")
    }

    @Test func theTimeoutClearsTheTransitionWhenNoFrameArrives() async throws {
        let camera = try makeCamera(timeout: .milliseconds(50))

        camera.flipCamera()
        #expect(camera.isSwitchingCamera)
        await settle(camera)

        #expect(!camera.isSwitchingCamera)
        #expect(camera.flipTransition == nil)
        #expect(camera.cameraPosition == .front, "a slow camera is not a failed one")
    }

    @Test func aLensChangeSwitchesWithoutTheFlipTransition() async throws {
        let gate = Gate()
        let camera = try makeCamera(gate: gate)

        camera.selectLens(.telephoto)
        #expect(camera.isSwitchingCamera)
        #expect(camera.flipTransition == nil)
        #expect(camera.selectedLens == .telephoto)

        gate.open()
        await settle(camera)
        #expect(!camera.isSwitchingCamera)
    }

    @Test func theFrameSinkForgetsItsFrameAndReleasesWaiters() async {
        let sink = FilmPreviewFrameSink()
        sink.reset()
        #expect(sink.newestFrame() == nil)

        let waiter = Task { await sink.nextFrame() }
        for _ in 0..<5 { await Task.yield() }
        sink.cancelWaiting()
        await waiter.value
    }
}
