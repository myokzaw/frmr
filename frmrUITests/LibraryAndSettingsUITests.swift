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
        app.segmentedControls.buttons["Entries"].tap()
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
        let clearRoll = app.buttons["settings.clearRoll"]
        for _ in 0..<5 where !clearRoll.isHittableNow { app.swipeUp() }
        XCTAssertTrue(clearRoll.waitForExistence(timeout: timeout))
        clearRoll.tap()
        XCTAssertTrue(app.buttons["settings.clearRoll.confirm"].waitForExistence(timeout: timeout), "Keep entries (the default) missing")
        XCTAssertTrue(app.buttons["settings.clearRoll.deleteBoth"].exists, "Delete photos and diary entries missing")
        saveScreenshot(named: "restyle-settings-clear-roll")
        app.buttons["settings.clearRoll.confirm"].firstMatch.tap()
        openRoll(app)
        XCTAssertTrue(app.buttons["roll.takePhoto"].waitForExistence(timeout: timeout), "The Roll is empty")
        app.segmentedControls.buttons["Entries"].tap()
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
        app.launchArguments = ["-UITestFast"]
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

        let suffix = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] ?? "light"
        let cases = [("Off", "none"), ("Mono 400", "mono400"), ("Cine 500T", "cine500T"), (asShot, "asShot")]
        for (stock, file) in cases {
            select(stock, in: stockPicker, app: app)
            XCTAssertTrue(shows(stock, picker: stockPicker), "\(stock): picker should show the choice")
            let blackAndWhite = app.switches["settings.blackAndWhite"]
            for _ in 0..<3 where !blackAndWhite.isHittableNow { app.swipeUp() }
            XCTAssertTrue(blackAndWhite.waitForExistence(timeout: timeout))
            // v5.2 S6: the effect defaults moved to the Default look page
            let defaultLook = app.buttons["settings.defaultLook"]
            _ = defaultLook.waitForExistence(timeout: 1)
            XCTAssertEqual(defaultLook.exists, stock != "Off", "\(stock): effects visibility")
            XCTAssertEqual(blackAndWhite.isEnabled, !monoStocks.contains(stock), "\(stock): B&W lock")
            if monoStocks.contains(stock) {
                XCTAssertEqual(blackAndWhite.value as? String, "1", "\(stock): B&W should read on")
            }
            if stock == asShot {
                XCTAssertFalse(app.buttons["Print"].exists, "As shot: no print row")
            }
            saveScreenshot(named: "settings-strip-defaults-\(file)-\(suffix)")
            for _ in 0..<3 where !stockPicker.isHittableNow { app.swipeDown() }
        }
        // The loop ends on As shot, the v4 F12 default, so the simulator's
        // stored default is left at the new default
    }

    // v5.2 S6: the camera toggles default on and persist; Default look is
    // its own page with the editor's tool bar and scrubber
    @MainActor
    func testSettingsCameraTogglesAndDefaultLookPage() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()
        let edit = app.switches["settings.editAfterEachShot"]
        let haptics = app.switches["settings.filmAdvanceHaptics"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout), "Edit after each shot missing")
        XCTAssertTrue(haptics.exists, "Film-advance haptics missing")
        XCTAssertEqual(edit.value as? String, "1", "Edit after each shot defaults on")
        XCTAssertEqual(haptics.value as? String, "1", "Film-advance haptics defaults on")
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        saveScreenshot(named: "settings-camera-toggles")

        // Off survives a relaunch; the test leaves it on again
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(edit, "0"), "Edit after each shot should turn off")
        app.terminate()
        let relaunched = launchSeeded()
        relaunched.tabBars.buttons["Settings"].tap()
        let editAgain = relaunched.switches["settings.editAfterEachShot"]
        XCTAssertTrue(editAgain.waitForExistence(timeout: timeout))
        XCTAssertEqual(editAgain.value as? String, "0", "The setting persists")
        editAgain.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(editAgain, "1"))

        let defaultLook = relaunched.buttons["settings.defaultLook"]
        for _ in 0..<3 where !defaultLook.isHittableNow { relaunched.swipeUp() }
        guard defaultLook.exists else { return }  // stock default is Off: no effects page
        defaultLook.tap()
        let scrubber = relaunched.descendants(matching: .any)["settings.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: timeout), "Default look scrubber missing")
        for effect in ["halation", "haze", "lightLeak", "grain", "vignette"] {
            XCTAssertTrue(relaunched.buttons["settings.tool.\(effect)"].exists, "\(effect) tool missing")
        }
        relaunched.buttons["settings.tool.grain"].tap()
        XCTAssertTrue(relaunched.buttons["settings.tool.grain"].isSelected)
        XCTAssertTrue((scrubber.value as? String)?.hasSuffix("%") == true)
        saveScreenshot(named: "settings-default-look")
    }

    // BUG-521-02: with Edit after each shot off, a Roll photo without an
    // entry still offers Continue to diary, and the prompt opens in place
    @MainActor
    func testRollReEditContinuesToDiary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFast", "-UITestSeedRoll", "-UITestSeedLibrary", "-editAfterEachShot", "NO"]
        app.launch()
        dismissInAppOverlays(app)
        openRoll(app)
        let plain = app.buttons.matching(identifier: "roll.photo")
            .matching(NSPredicate(format: "NOT (label CONTAINS %@)", linkedMarker)).firstMatch
        XCTAssertTrue(plain.waitForExistence(timeout: timeout))
        plain.tap()
        let diary = app.buttons["edit.continueDiary"]
        XCTAssertTrue(diary.waitForExistence(timeout: timeout), "Re-edit of a photo with no entry offers Continue to diary")
        diary.tap()
        XCTAssertTrue(app.buttons["entry.save"].waitForExistence(timeout: timeout), "The prompt opens in the same cover")
    }

    // F-GRID: Settings > Grid > Thirds shows the overlay on the camera
    @MainActor
    func testGridSettingShowsOverlayOnCamera() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()
        let grid = app.buttons["settings.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: timeout), "Grid picker missing")
        grid.tap()
        app.buttons["Thirds"].tap()
        app.tabBars.buttons["Camera"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera.grid"].waitForExistence(timeout: timeout), "Grid overlay missing")
    }

    // MARK: Viewers

    @MainActor
    func testEntryAndStripViewersOpenAndClose() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Library"].tap()
        let entries = app.segmentedControls.buttons["Entries"]
        XCTAssertTrue(entries.waitForExistence(timeout: timeout))
        entries.tap()
        let entry = app.buttons["library.entry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: timeout), "Seeded entry missing")
        entry.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: timeout), "Entry viewer has a close icon")
        XCTAssertTrue(app.otherElements["detail.footer"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Morning light")).firstMatch.exists, "Entry text missing")
        app.buttons["detail.close"].tap()
        XCTAssertTrue(app.buttons["library.entry"].firstMatch.waitForExistence(timeout: timeout), "Close returns to the list")

        app.segmentedControls.buttons["Strips"].tap()
        let strip = app.buttons["library.strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: timeout), "Seeded strip missing")
        strip.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: timeout), "Strip viewer has a close icon")
        XCTAssertTrue(app.buttons["detail.save"].exists, "Strip viewer offers Save to camera roll")
        app.buttons["detail.close"].tap()
        XCTAssertTrue(app.buttons["library.strip"].firstMatch.waitForExistence(timeout: timeout), "Close returns to the strips")
    }

    // Make today's strip asks which entries first; unpicking one drops the
    // counter, and Make strip opens the strip screen
    @MainActor
    func testMakeTodaysStripPicksEntriesFirst() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Library"].tap()
        let strips = app.segmentedControls.buttons["Strips"]
        XCTAssertTrue(strips.waitForExistence(timeout: timeout))
        strips.tap()
        let plus = app.buttons["library.makeTodaysStrip"]
        XCTAssertTrue(plus.waitForExistence(timeout: timeout), "Seeded entry today should offer the strip")
        plus.tap()

        let entry = app.buttons["library.entryPicker.entry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: timeout), "Entry picker missing")
        let counter = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'picked'")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: timeout), "Counter title missing")
        let before = counter.label
        // Newest first, so the default picks are at the top of the grid
        let picked = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Entry, picked'"))
        XCTAssertGreaterThan(picked.count, 0, "Today's latest entries start picked")
        // Tap the same tile twice by position: its label changes on unpick,
        // and "first unpicked" can resolve to a tile scrolled off screen
        // (a coordinate made from the query re-resolves at tap time, so fix
        // the screen point from the frame once)
        let frame = picked.firstMatch.frame
        let tile = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        tile.tap()
        XCTAssertNotEqual(counter.label, before, "Counter drops")
        tile.tap()
        XCTAssertEqual(counter.label, before, "Picking again restores the counter")

        app.buttons["library.entryPicker.make"].tap()
        XCTAssertTrue(app.buttons["strip.keep"].waitForExistence(timeout: timeout), "Make strip opens the strip screen")
    }

    // Discard asks first; confirming deletes the strip and closes the viewer.
    // The fixture reseeds a strip on the next launch.
    @MainActor
    func testDeletingAStripFromItsViewer() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["Strips"].tap()
        let strips = app.buttons.matching(identifier: "library.strip")
        XCTAssertTrue(strips.firstMatch.waitForExistence(timeout: timeout), "Seeded strip missing")
        let before = strips.count
        strips.firstMatch.tap()
        let delete = app.buttons["strip.detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout), "Discard missing")
        delete.tap()
        let confirm = app.buttons["strip.detail.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout), "Delete asks first")
        confirm.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForNonExistence(timeout: timeout), "Viewer closes")
        XCTAssertTrue(app.segmentedControls.buttons["Strips"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons.matching(identifier: "library.strip").count, before - 1)
    }

    // Settings > Clear strips empties the Strips tab and keeps the entries
    @MainActor
    func testClearStripsEmptiesTheStripsTab() throws {
        let app = launchSeeded()
        app.tabBars.buttons["Settings"].tap()
        let clear = app.buttons["settings.clearStrips"]
        for _ in 0..<4 where !clear.isHittableNow { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: timeout), "Clear strips missing")
        clear.tap()
        let confirm = app.buttons["settings.clearStrips.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout), "Clear strips asks first")
        confirm.tap()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["Strips"].tap()
        XCTAssertTrue(app.staticTexts["No strips yet"].waitForExistence(timeout: timeout), "Strips tab shows its empty state")
        XCTAssertEqual(app.buttons.matching(identifier: "library.strip").count, 0)
    }

    // MARK: Steps

    @MainActor
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFast", "-UITestSeedRoll", "-UITestSeedLibrary"]
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
        let roll = app.segmentedControls.buttons["Roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: timeout))
        roll.tap()
    }

    private func rollCount(in app: XCUIApplication) -> Int {
        _ = app.buttons["roll.photo"].firstMatch.waitForExistence(timeout: timeout)
        return frameCount(in: app)
    }

    private func waitForRollCount(_ app: XCUIApplication, equals expected: Int) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if frameCount(in: app) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
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

/// The Roll's photo count from its day headers ("Today, 12 frames"); the
/// lazy contact sheet only builds the cells on screen, so counting cells
/// undercounts a long Roll. Seeded photos are all from today.
func frameCount(in app: XCUIApplication) -> Int {
    let headers = app.descendants(matching: .any).matching(identifier: "roll.dayHeader")
    return headers.allElementsBoundByIndex.reduce(0) { total, header in
        let digits = header.label.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        return total + (digits.last.flatMap(Int.init) ?? 0)
    }
}

extension XCUIElement {
    /// On screen and tappable now; false (never throws) when it isn't there.
    var isHittableNow: Bool { exists && isHittable }
}
