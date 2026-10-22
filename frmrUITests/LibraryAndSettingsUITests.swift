import XCTest

// v5.1 F7/F10: the Library (Roll badge, delete and Clear roll prompts, entry
// and strip viewers) and Settings strip defaults. The simulator has no
// camera, so data comes from the DEBUG-only launch arguments
// `-UITestSeedRoll` (three Roll photos per launch) and `-UITestSeedLibrary`
// (an entry linked to the newest photo, plus once per simulator an older
// entry and a saved strip).
final class LibraryAndSettingsUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    private let asShot = "As shot"
    private let monoStocks: Set<String> = ["Mono 400", "Mono 3200"]
    private let linkedMarker = "has a diary entry"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Roll

    @MainActor
    func testRollMarksPhotosWithADiaryEntry() throws {
        let app = launchSeeded()
        openRoll(app)
        XCTAssertTrue(app.buttons["roll.photo"].firstMatch.waitForExistence(timeout: timeout))
        let badged = app.buttons.matching(identifier: "roll.photo")
            .matching(NSPredicate(format: "label CONTAINS %@", linkedMarker))
        XCTAssertGreaterThanOrEqual(badged.count, 1, "The photo with an entry carries the book badge")
        let plain = app.buttons.matching(identifier: "roll.photo")
            .matching(NSPredicate(format: "NOT (label CONTAINS %@)", linkedMarker))
        XCTAssertGreaterThanOrEqual(plain.count, 1, "Photos without an entry carry no badge")
        saveScreenshot(named: "restyle-roll-badge")
    }

    @MainActor
    func testDeletingAPhotoWithAnEntryAsksWhatToDoWithIt() throws {
        let app = launchSeeded()
        openRoll(app)
        let before = rollCount(in: app)
        app.buttons["roll.select"].tap()
        let badged = app.buttons.matching(identifier: "roll.photo")
            .matching(NSPredicate(format: "label CONTAINS %@", linkedMarker))
        badged.firstMatch.tap()
        app.buttons["roll.delete"].tap()
        XCTAssertTrue(app.buttons["roll.delete.keepEntries"].waitForExistence(timeout: timeout), "Keep entries missing")
        XCTAssertTrue(app.buttons["roll.delete.deleteBoth"].exists, "Delete photos and diary entries missing")
        XCTAssertFalse(app.buttons["roll.delete.confirm"].exists, "A photo with an entry gets the two-way prompt")
        saveScreenshot(named: "restyle-roll-delete-prompt")
        app.buttons["roll.delete.keepEntries"].firstMatch.tap()

        XCTAssertTrue(waitForRollCount(app, equals: before - 1), "Deleting removes the photo")
        // Keep entries: the entry survives with its own copy of the photo
        app.buttons["library.tab.entries"].tap()
        XCTAssertTrue(app.buttons["library.entry"].firstMatch.waitForExistence(timeout: timeout), "The entry was kept")
    }

    @MainActor
    func testDeletingAPhotoWithoutAnEntryAsksPlainly() throws {
        let app = launchSeeded()
        openRoll(app)
        let before = rollCount(in: app)
        app.buttons["roll.select"].tap()
        let plain = app.buttons.matching(identifier: "roll.photo")
            .matching(NSPredicate(format: "NOT (label CONTAINS %@)", linkedMarker))
        plain.firstMatch.tap()
        app.buttons["roll.delete"].tap()
        XCTAssertTrue(app.buttons["roll.delete.confirm"].waitForExistence(timeout: timeout), "Delete confirm missing")
        XCTAssertFalse(app.buttons["roll.delete.keepEntries"].exists, "No entry, no choice to make")
        app.buttons["roll.delete.confirm"].firstMatch.tap()
        XCTAssertTrue(waitForRollCount(app, equals: before - 1), "Deleting removes the photo")
    }

    // MARK: Settings

    @MainActor
    func testClearRollOffersKeepOrDeleteEntries() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.filmStock"].waitForExistence(timeout: timeout))
        app.swipeUp()
        app.swipeUp()
        let clearRoll = app.buttons["settings.clearRoll"]
        XCTAssertTrue(clearRoll.waitForExistence(timeout: timeout))
        clearRoll.tap()
        XCTAssertTrue(app.buttons["settings.clearRoll.confirm"].waitForExistence(timeout: timeout), "Keep entries (the default) missing")
        XCTAssertTrue(app.buttons["settings.clearRoll.deleteBoth"].exists, "Delete photos and diary entries missing")
        saveScreenshot(named: "restyle-settings-clear-roll")
        app.buttons["settings.clearRoll.confirm"].firstMatch.tap()
        openRoll(app)
        XCTAssertTrue(app.buttons["roll.takePhoto"].waitForExistence(timeout: timeout), "The Roll is empty")
        app.buttons["library.tab.entries"].tap()
        XCTAssertTrue(app.buttons["library.entry"].firstMatch.waitForExistence(timeout: timeout), "Keep entries leaves the diary")
    }

    // OBS-V4-4: Settings → Strip defaults follows the strip screen's rules
    // (effects hidden for Off, B&W on and locked for mono stocks). F12: As
    // shot has no print row, keeps effects and leaves B&W unlocked. F8: the
    // Background picker offers White and Black only.
    // TEST_RUNNER_SHOTS_SUFFIX=light|dark names the saved screenshots.
    @MainActor
    func testSettingsStripDefaultsMirrorStripRules() throws {
        let app = XCUIApplication()
        app.launch()
        dismissInAppOverlays(app)
        app.tabBars.buttons["Settings"].tap()
        let stockPicker = app.buttons["settings.filmStock"]
        XCTAssertTrue(stockPicker.waitForExistence(timeout: timeout))

        let background = app.buttons["settings.background"]
        XCTAssertTrue(background.waitForExistence(timeout: timeout), "Background picker missing")
        background.tap()
        XCTAssertTrue(app.buttons["White"].firstMatch.waitForExistence(timeout: timeout), "White missing")
        XCTAssertTrue(app.buttons["Black"].firstMatch.exists, "Black missing")
        XCTAssertFalse(app.buttons["Cream"].exists, "Cream should be gone (v4 F8)")
        app.buttons["White"].firstMatch.tap()
        // The effect sliders and B&W sit below the fold; List rows only exist on screen
        app.swipeUp()

        let suffix = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] ?? "light"
        let cases = [("Off", "none"), ("Mono 400", "mono400"), ("Cine 500T", "cine500T"), (asShot, "asShot")]
        for (stock, file) in cases {
            // The picker row scrolls off with the taller slider rows; bring it back
            app.swipeDown()
            select(stock, in: stockPicker, app: app)
            XCTAssertTrue(shows(stock, picker: stockPicker), "\(stock): picker should show the choice")
            app.swipeUp()
            let blackAndWhite = app.switches["settings.blackAndWhite"]
            XCTAssertTrue(blackAndWhite.waitForExistence(timeout: timeout))
            _ = app.sliders["settings.slider.halation"].waitForExistence(timeout: 1)
            XCTAssertEqual(app.sliders["settings.slider.halation"].exists, stock != "Off", "\(stock): effects visibility")
            XCTAssertEqual(blackAndWhite.isEnabled, !monoStocks.contains(stock), "\(stock): B&W lock")
            if monoStocks.contains(stock) {
                XCTAssertEqual(blackAndWhite.value as? String, "1", "\(stock): B&W should read on")
            }
            if stock == asShot {
                XCTAssertFalse(app.buttons["Print"].exists, "As shot: no print row")
            }
            saveScreenshot(named: "settings-strip-defaults-\(file)-\(suffix)")
        }
        // The loop ends on As shot, the v4 F12 default, so the simulator's
        // stored default is left at the new default
    }

    // MARK: Viewers

    @MainActor
    func testEntryAndStripViewersOpenAndClose() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Library"].tap()
        let entries = app.buttons["library.tab.entries"]
        XCTAssertTrue(entries.waitForExistence(timeout: timeout))
        entries.tap()
        let entry = app.buttons["library.entry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: timeout), "Seeded entry missing")
        entry.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: timeout), "Entry viewer has a close icon")
        XCTAssertTrue(app.otherElements["detail.footer"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Morning light")).firstMatch.exists, "Entry text missing")
        app.buttons["detail.close"].tap()
        XCTAssertTrue(app.buttons["library.entry"].firstMatch.waitForExistence(timeout: timeout), "Close returns to the list")

        app.buttons["library.tab.strips"].tap()
        let strip = app.buttons["library.strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: timeout), "Seeded strip missing")
        strip.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: timeout), "Strip viewer has a close icon")
        XCTAssertTrue(app.buttons["detail.save"].exists, "Strip viewer offers Save to camera roll")
        app.buttons["detail.close"].tap()
        XCTAssertTrue(app.buttons["library.strip"].firstMatch.waitForExistence(timeout: timeout), "Close returns to the strips")
    }

    // MARK: Steps

    @MainActor
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestSeedRoll", "-UITestSeedLibrary"]
        app.launch()
        dismissInAppOverlays(app)
        return app
    }

    private func dismissInAppOverlays(_ app: XCUIApplication) {
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
        _ = skip.waitForNonExistence(timeout: 3)
    }

    private func openRoll(_ app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
        let roll = app.buttons["library.tab.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: timeout))
        roll.tap()
    }

    private func rollCount(in app: XCUIApplication) -> Int {
        _ = app.buttons["roll.photo"].firstMatch.waitForExistence(timeout: timeout)
        return app.buttons.matching(identifier: "roll.photo").count
    }

    private func waitForRollCount(_ app: XCUIApplication, equals expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons.matching(identifier: "roll.photo").count == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func select(_ stock: String, in picker: XCUIElement, app: XCUIApplication) {
        picker.tap()
        let item = app.buttons[stock].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: timeout), "Menu item \(stock) missing")
        item.tap()
    }

    // A menu Picker's button reports its value in the label or the value,
    // depending on the context it sits in
    private func shows(_ choice: String, picker: XCUIElement) -> Bool {
        picker.label.contains(choice) || (picker.value as? String)?.contains(choice) == true
    }

    private func saveScreenshot(named name: String) {
        sleep(1)
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
