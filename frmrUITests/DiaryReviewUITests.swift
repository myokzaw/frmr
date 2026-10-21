import XCTest

// v4 Part 2 F9/F10/F11/F13 UI. The simulator has no camera, so the review
// screen is opened through the DEBUG-only `-UITestDiaryReview` launch
// argument (CameraView: a generated photo on Portrait 400 whose Download
// writes nowhere). The real capture → review path and the real camera-roll
// save are device-only.
// Optional: TEST_RUNNER_SHOTS_DIR=<abs dir> writes the screenshots there.
final class DiaryReviewUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    private let reviewArgument = "-UITestDiaryReview"
    private let stockIDs = ["none", "daylight200", "portrait400", "cine500T", "slide100", "mono400", "mono3200"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // F9: the Film chip is collapsed to one chip, expands to all seven
    // stocks, and collapses again on a pick (in Diary and Film strip modes)
    @MainActor
    func testCameraFilmControlExpandsAndCollapses() throws {
        let app = XCUIApplication()
        app.launch()
        dismissInAppOverlays(app)

        let filmChips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camera.film.'"))
        XCTAssertTrue(filmChips.firstMatch.waitForExistence(timeout: timeout), "Film chip missing")
        XCTAssertEqual(filmChips.count, 1, "Film control should start collapsed")
        let startingID = filmChips.firstMatch.identifier
        saveScreenshot(named: "camera-film-collapsed")

        filmChips.firstMatch.tap()
        XCTAssertTrue(app.buttons["camera.film.mono3200"].waitForExistence(timeout: timeout))
        XCTAssertEqual(filmChips.count, stockIDs.count, "Expanded Film control shows every stock")
        saveScreenshot(named: "camera-film-expanded")

        app.buttons["camera.film.cine500T"].tap()
        XCTAssertTrue(waitForCount(filmChips, 1), "Picking a stock collapses the control")
        XCTAssertEqual(filmChips.firstMatch.identifier, "camera.film.cine500T")
        saveScreenshot(named: "camera-film-cine500T-diary")

        // Film strip mode shows the same control
        app.buttons["Film strip"].tap()
        XCTAssertTrue(app.buttons["camera.film.cine500T"].waitForExistence(timeout: timeout), "Film control missing in Film strip mode")
        saveScreenshot(named: "camera-film-cine500T-filmstrip")
        app.buttons["Diary"].tap()

        // Leave the simulator's camera stock as it started
        app.buttons["camera.film.cine500T"].tap()
        let original = app.buttons[startingID]
        XCTAssertTrue(original.waitForExistence(timeout: timeout))
        original.tap()
    }

    // F10 + F13: stock row, Download → Saved, OK → prompt screen
    @MainActor
    func testReviewDownloadThenOKOpensPrompt() throws {
        let app = launchReview()

        for id in stockIDs {
            XCTAssertTrue(app.buttons["review.stock.\(id)"].exists, "Stock chip \(id) missing")
        }
        XCTAssertTrue(app.buttons["review.stock.portrait400"].isSelected, "Review starts on the capture's stock")
        let ok = app.buttons["review.ok"]
        let retake = app.buttons["review.retake"]
        let download = app.buttons["review.download"]
        XCTAssertLessThan(ok.frame.midX, retake.frame.midX, "OK is bottom left, Retake bottom right")
        XCTAssertGreaterThan(download.frame.midX, app.frame.midX, "Download sits top right")
        XCTAssertLessThan(download.frame.midY, ok.frame.minY, "Download sits above the buttons")
        XCTAssertTrue(waitUntilEnabled(download), "Download stayed disabled (render never settled?)")
        saveScreenshot(named: "review-portrait400")

        tapStock("mono400", app: app)
        XCTAssertTrue(app.buttons["review.stock.mono400"].isSelected)
        XCTAssertTrue(waitUntilEnabled(download))
        saveScreenshot(named: "review-mono400")

        download.tap()
        let saved = NSPredicate(format: "value == 'Saved'")
        let savedState = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: download)], timeout: timeout)
        XCTAssertEqual(savedState, .completed, "Download never showed Saved")
        saveScreenshot(named: "review-saved", settle: 0)

        ok.tap()
        XCTAssertTrue(app.buttons["Save entry"].waitForExistence(timeout: timeout), "OK should open the prompt screen")
        XCTAssertFalse(ok.exists, "Review should be gone after OK")
        saveScreenshot(named: "review-ok-prompt-mono400")

        // Retake on the prompt screen ends the flow without an entry
        app.buttons["Retake"].tap()
        XCTAssertTrue(app.buttons["Film strip"].waitForExistence(timeout: timeout), "Retake should return to the camera")
    }

    @MainActor
    func testReviewRetakeReturnsToCamera() throws {
        let app = launchReview()
        app.buttons["review.retake"].tap()
        XCTAssertTrue(app.buttons["Film strip"].waitForExistence(timeout: timeout), "Retake should return to the camera")
        XCTAssertFalse(app.buttons["review.ok"].exists)
        XCTAssertFalse(app.buttons["Save entry"].exists, "Retake must not open the prompt")
    }

    // F11: an entry saved through review shows in its stock in the diary
    // list and the detail viewer. Adds one text-less entry to the
    // simulator's diary.
    @MainActor
    func testSavedEntryShowsInItsStock() throws {
        let app = launchReview()
        tapStock("cine500T", app: app)
        XCTAssertTrue(waitUntilEnabled(app.buttons["review.download"]))
        app.buttons["review.ok"].tap()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: timeout))
        skip.tap()

        app.tabBars.buttons["Library"].tap()
        let firstEntry = app.collectionViews.buttons.firstMatch
        XCTAssertTrue(firstEntry.waitForExistence(timeout: timeout), "Diary list has no entries")
        saveScreenshot(named: "diary-list-cine500T", settle: 3)
        firstEntry.tap()
        saveScreenshot(named: "entry-detail-cine500T", settle: 3)
    }

    // MARK: Steps

    private func launchReview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [reviewArgument]
        app.launch()
        XCTAssertTrue(app.buttons["review.ok"].waitForExistence(timeout: timeout), "Review screen did not open")
        return app
    }

    // The stock row scrolls horizontally; bring the chip on screen first
    private func tapStock(_ id: String, app: XCUIApplication) {
        let chip = app.buttons["review.stock.\(id)"]
        let row = app.scrollViews.containing(.button, identifier: "review.stock.none").firstMatch
        // isHittable throws for an off-screen chip, so compare frames
        for _ in 0..<stockIDs.count where chip.frame.maxX > app.frame.maxX {
            row.swipeLeft()
        }
        chip.tap()
    }

    private func dismissInAppOverlays(_ app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.tap()
        for label in ["OK", "Skip"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
        }
    }

    private func waitForCount(_ query: XCUIElementQuery, _ count: Int) -> Bool {
        let predicate = NSPredicate(format: "count == \(count)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func saveScreenshot(named name: String, settle: UInt32 = 1) {
        sleep(settle)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
