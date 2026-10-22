import XCTest

// Screenshot tour of the Library, detail viewers, Settings and walkthrough
// for the v5.1 F10 before/after review. Skipped unless
// TEST_RUNNER_SHOTS_DIR=<abs dir> is set (xcodebuild forwards it as
// SHOTS_DIR). TEST_RUNNER_SHOTS_PREFIX=before|after names the files.
// Uses the DEBUG fixtures -UITestSeedRoll and -UITestSeedLibrary; the Clear
// roll step at the end empties the simulator's Roll.
final class LibraryScreenshotTour: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["SHOTS_DIR"] == nil, "Set TEST_RUNNER_SHOTS_DIR to take the tour")
    }

    @MainActor
    func testTourLight() throws { try tour(mode: "light") }

    @MainActor
    func testTourDark() throws { try tour(mode: "dark") }

    @MainActor
    private func tour(mode: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedRoll", "-UITestSeedLibrary", "-appearanceMode", mode]
        app.launch()
        dismissInAppOverlays(app)

        // Walkthrough bubble (replayed from Settings)
        app.tabBars.buttons["Settings"].tap()
        if !app.buttons["settings.filmStock"].waitForExistence(timeout: timeout) {
            shot("debug-settings", mode)
        }
        XCTAssertTrue(app.buttons["settings.filmStock"].exists)
        shot("settings-top", mode)
        app.swipeUp()
        shot("settings-sliders", mode)
        app.swipeUp()
        shot("settings-bottom", mode)
        let replay = app.buttons["Show intro again"]
        XCTAssertTrue(replay.waitForExistence(timeout: timeout))
        replay.tap()
        sleep(2)
        shot("walkthrough", mode)
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 8) { skip.tap() }
        _ = skip.waitForNonExistence(timeout: 5)

        // Library: Roll
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons["roll.photo"].waitForExistence(timeout: timeout))
        shot("library-roll", mode, settle: 2)
        app.buttons["roll.select"].tap()
        let photos = app.buttons.matching(identifier: "roll.photo")
        photos.element(boundBy: 0).tap()
        photos.element(boundBy: 1).tap()
        shot("library-roll-select", mode)
        app.buttons["roll.cancelSelect"].tap()

        // Entries and its detail
        app.buttons["library.tab.entries"].tap()
        sleep(1)
        shot("library-entries", mode, settle: 2)
        let entry = app.buttons.element(boundBy: 0)
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Morning light")).firstMatch.tap()
        _ = entry
        sleep(2)
        shot("entry-detail", mode, settle: 1)
        closeDetail(app)

        // Strips and its detail
        app.buttons["library.tab.strips"].tap()
        XCTAssertTrue(app.buttons["library.strip"].firstMatch.waitForExistence(timeout: timeout))
        shot("library-strips", mode, settle: 2)
        app.buttons["library.strip"].firstMatch.tap()
        sleep(1)
        shot("strip-detail", mode)
        closeDetail(app)

        // Empty Roll
        app.tabBars.buttons["Settings"].tap()
        app.swipeUp()
        app.swipeUp()
        let clearRoll = app.buttons["settings.clearRoll"]
        XCTAssertTrue(clearRoll.waitForExistence(timeout: timeout))
        clearRoll.tap()
        sleep(1)
        shot("settings-clear-roll", mode)
        let confirm = app.buttons["settings.clearRoll.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()
        app.tabBars.buttons["Library"].tap()
        app.buttons["library.tab.roll"].tap()
        sleep(1)
        shot("library-roll-empty", mode, settle: 2)
    }

    private func closeDetail(_ app: XCUIApplication) {
        let close = app.buttons["Close"]
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.08)).tap()
        }
        sleep(1)
    }

    private func dismissInAppOverlays(_ app: XCUIApplication) {
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        _ = skip.waitForNonExistence(timeout: 3)
    }

    private func shot(_ name: String, _ mode: String, settle: UInt32 = 1) {
        sleep(settle)
        let screenshot = XCUIScreen.main.screenshot()
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["SHOTS_DIR"] else { return }
        let prefix = environment["SHOTS_PREFIX"] ?? "after"
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(prefix)-\(name)-\(mode).png")
        try? screenshot.pngRepresentation.write(to: url)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(prefix)-\(name)-\(mode)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
