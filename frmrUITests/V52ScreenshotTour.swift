import XCTest

// v5.2 before/after screenshot tour of every screen: camera (Photo, Film
// strip, WB sheet), editor (Film, Exposure/effect tool), prompt, strip
// screen, Library (Roll, Entries, Strips), the viewers and Settings, in light,
// dark and AX5 Dynamic Type. Skipped unless TEST_RUNNER_SHOTS_DIR=<abs dir>
// is set; TEST_RUNNER_SHOTS_PREFIX names the files (default "after"). A tour,
// not a test: a missing control is skipped instead of failing, so the same file shoots the before and the after UI. Uses the
// DEBUG fixtures (-UITestPhotoEdit, -UITestSeedRoll, -UITestSeedLibrary), so
// each run adds Roll photos and an entry to the simulator.
final class V52ScreenshotTour: XCTestCase {
    private let timeout: TimeInterval = 8
    private let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUpWithError() throws {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        try XCTSkipIf(ProcessInfo.processInfo.environment["SHOTS_DIR"] == nil, "Set TEST_RUNNER_SHOTS_DIR to take the tour")
    }

    @MainActor func testTourLight() { tour(mode: "light", extra: []) }
    @MainActor func testTourDark() { tour(mode: "dark", extra: []) }
    @MainActor func testTourAX5() { tour(mode: "ax5", extra: ax5) }

    @MainActor
    private func tour(mode: String, extra: [String]) {
        let scheme = mode == "dark" ? "dark" : "light"
        let base = ["-UITestFast", "-appearanceMode", scheme] + extra

        // Camera
        var app = launch(base + ["-UITestSeedRoll", "-UITestSeedLibrary"])
        shot("camera-photo", mode)
        tapIfPresent(app.buttons["camera.wb.chip"], mode)
        shot("camera-wb-sheet", mode)
        tapIfPresent(app.buttons["camera.wb.chip"], mode)
        tapIfPresent(app.buttons["camera.mode.filmstrip"], mode)
        shot("camera-filmstrip", mode)
        if app.buttons["strip.miniStrip"].waitForExistence(timeout: 2) {
            app.buttons["strip.miniStrip"].tap()
            shot("camera-filmstrip-sheet", mode)
            app.swipeDown()
        }
        tapIfPresent(app.buttons["camera.mode.photo"], mode)

        // Library
        app.tabBars.buttons["Library"].tap()
        shot("library-roll", mode, settle: 2)
        tapIfPresent(app.segmentedControls.buttons["Entries"], mode)
        shot("library-entries", mode, settle: 2)
        let entry = app.buttons["library.entry"].firstMatch
        if entry.waitForExistence(timeout: 2) {
            entry.tap()
            shot("entry-detail", mode, settle: 2)
            tapIfPresent(app.buttons["detail.close"], mode)
        }
        tapIfPresent(app.segmentedControls.buttons["Strips"], mode)
        shot("library-strips", mode, settle: 2)
        let strip = app.buttons["library.strip"].firstMatch
        if strip.waitForExistence(timeout: 2) {
            strip.tap()
            shot("strip-detail", mode)
            tapIfPresent(app.buttons["detail.close"], mode)
        }

        // Strip screen from Roll picks
        tapIfPresent(app.segmentedControls.buttons["Roll"], mode)
        if app.buttons["roll.select"].waitForExistence(timeout: 2) {
            app.buttons["roll.select"].tap()
            let cells = app.buttons.matching(identifier: "roll.photo")
            for index in 0..<min(3, cells.count) { cells.element(boundBy: index).tap() }
            shot("library-roll-select", mode)
            tapIfPresent(app.buttons["roll.makeStrip"], mode)
            shot("strip-screen", mode, settle: 3)
            if app.buttons["strip.tool.halation"].waitForExistence(timeout: 2) {
                app.buttons["strip.tool.halation"].tap()
                shot("strip-screen-halation", mode, settle: 2)
            }
            if app.buttons["strip.close"].exists { app.buttons["strip.close"].tap() } else { tapIfPresent(app.buttons["Close"], mode) }
            if app.buttons["roll.cancelSelect"].waitForExistence(timeout: 2) { app.buttons["roll.cancelSelect"].tap() }
        }

        // Settings
        app.tabBars.buttons["Settings"].tap()
        shot("settings-top", mode)
        app.swipeUp()
        shot("settings-middle", mode)
        app.swipeUp()
        app.swipeUp()
        shot("settings-bottom", mode)
        app.terminate()

        // Editor, then the prompt screen
        app = launch(base + ["-UITestPhotoEdit"])
        _ = app.buttons["edit.save"].waitForExistence(timeout: timeout)
        shot("edit-open", mode, settle: 2)
        tapIfPresent(app.buttons["edit.tool.film"], mode)
        shot("edit-film", mode, settle: 3)
        tapIfPresent(app.buttons["edit.tool.print"], mode)
        shot("edit-print", mode, settle: 2)
        tapIfPresent(app.buttons["edit.tool.halation"], mode)
        shot("edit-halation", mode)
        if app.buttons["edit.tool.exposure"].exists {
            app.buttons["edit.tool.exposure"].tap()
            shot("edit-exposure", mode)
        }
        tapIfPresent(app.buttons["edit.continueDiary"], mode)
        shot("diary-prompt", mode, settle: 3)
        app.terminate()
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Allow Full Access"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        app.tap()
        for _ in 0..<2 {
            for label in ["OK", "Skip"] {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 2) { button.tap() }
            }
        }
        return app
    }

    private func tapIfPresent(_ element: XCUIElement, _ mode: String) {
        // A control the UI under test doesn't have is skipped, not failed
        if element.waitForExistence(timeout: timeout), element.isHittable {
            element.tap()
        }
    }

    private func shot(_ name: String, _ mode: String, settle: UInt32 = 1) {
        if settle > 0 { sleep(settle) }
        let screenshot = XCUIScreen.main.screenshot()
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SHOTS_DIR"] else { return }
        let prefix = environment["SHOTS_PREFIX"].map { "\($0)-" } ?? ""
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)\(name)-\(mode).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}
