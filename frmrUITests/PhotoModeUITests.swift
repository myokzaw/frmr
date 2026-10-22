import XCTest

// v5 / v5.1 UI: the camera chrome shared by Photo and Film strip (F1, F8,
// F9), the white balance and exposure sheets, the editor with its icon
// toolbar and tick-mark scrubber (F2, F3, F8), and the Roll (F6). The
// simulator has no camera, so the editor is reached through the DEBUG-only
// `-UITestPhotoEdit` launch argument (a generated photo whose Download writes
// nowhere; Save to roll really saves), and a Roll with photos through
// `-UITestSeedRoll` (three generated photos added per launch). Every launch
// also passes `-UITestFast` (animations off). Real capture, the camera-roll
// save, haptics and rotation are device-only.
// Optional: TEST_RUNNER_SHOTS_DIR=<abs dir> writes the screenshots there.
final class PhotoModeUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    private let editArgument = "-UITestPhotoEdit"
    private let seedArgument = "-UITestSeedRoll"
    private let stockIDs = ["none", "daylight200", "portrait400", "cine500T", "slide100", "mono400", "mono3200"]
    private let effectIDs = ["halation", "haze", "lightLeak", "grain", "vignette"]
    private let toolIDs = ["film", "print", "halation", "haze", "lightLeak", "grain", "vignette"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: F1, F8, F9 camera chrome

    @MainActor
    func testPhotoAndFilmStripShareOneCameraChrome() throws {
        let app = launch()

        // F1 / v5.1-9: two modes, a small switch at the top left, Photo selected
        let photo = app.buttons["camera.mode.photo"]
        let strip = app.buttons["camera.mode.filmstrip"]
        XCTAssertTrue(photo.waitForExistence(timeout: timeout), "Photo mode button missing")
        XCTAssertEqual([photo.label, strip.label], ["Photo", "Film strip"])
        XCTAssertFalse(app.buttons["camera.mode.diary"].exists, "Diary is no longer a camera mode")
        XCTAssertLessThan(photo.frame.midX, strip.frame.midX)
        XCTAssertLessThan(strip.frame.midX, app.frame.midX, "The mode switch sits top left")
        XCTAssertLessThan(photo.frame.midY, app.frame.height * 0.2, "The mode switch sits at the top")
        XCTAssertTrue(photo.isSelected, "The app opens in Photo mode")
        XCTAssertFalse(strip.isSelected)

        // F8: WB and EV are small icons at the top right
        let wb = app.buttons["camera.wb.chip"]
        let ev = app.buttons["camera.ev.chip"]
        XCTAssertTrue(wb.exists && ev.exists, "WB and EV buttons missing")
        XCTAssertGreaterThan(wb.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(ev.frame.midX, wb.frame.midX)
        XCTAssertEqual(wb.frame.midY, photo.frame.midY, accuracy: 12, "Top bar items share a row")

        // The dial shows every stock; the old Film chip is gone
        for id in stockIDs {
            XCTAssertTrue(app.buttons["camera.dial.\(id)"].exists, "Dial detent \(id) missing")
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camera.film.'")).firstMatch.exists, "The Film chip is gone")
        let shutter = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.exists)
        let dial = app.descendants(matching: .any)["camera.dial"]
        XCTAssertLessThan(dial.frame.maxY, shutter.frame.minY, "The dial sits above the shutter")
        let photoDial = dial.frame
        let photoShutter = shutter.frame
        saveScreenshot(named: "camera-photo")

        // Tapping a detent selects that stock; swiping moves to a neighbour
        let target = app.buttons["camera.dial.cine500T"]
        target.tap()
        XCTAssertTrue(waitUntilSelected(target), "Tapping a detent selects it")
        saveScreenshot(named: "camera-photo-dial-cine500T")
        target.swipeLeft(velocity: .slow)
        XCTAssertTrue(waitUntilNotSelected(target), "Swiping the dial leaves the previous stock")
        XCTAssertEqual(stockIDs.filter { app.buttons["camera.dial.\($0)"].isSelected }.count, 1, "Exactly one stock is selected")

        // F9: Film strip is the same screen plus a strip layer
        strip.tap()
        XCTAssertTrue(waitUntilSelected(strip))
        XCTAssertTrue(app.buttons["camera.dial.none"].waitForExistence(timeout: timeout), "Film strip uses the same dial")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camera.film.'")).firstMatch.exists, "No Film chip in Film strip mode")
        XCTAssertEqual(dial.frame, photoDial, "The dial does not move between modes")
        XCTAssertEqual(shutter.frame, photoShutter, "The shutter does not move between modes")
        XCTAssertTrue(app.buttons["camera.wb.chip"].exists && app.buttons["camera.ev.chip"].exists)
        let count = app.staticTexts["strip.count"]
        XCTAssertTrue(count.waitForExistence(timeout: timeout), "The strip count is missing")
        XCTAssertEqual(count.label, "Captured 0 of 4")
        XCTAssertLessThan(count.frame.maxY, dial.frame.minY, "The slots sit above the dial")
        XCTAssertTrue(app.buttons["strip.gallery"].exists, "Gallery picker missing")
        XCTAssertTrue(app.buttons["strip.pickRoll"].exists, "Pick from Roll missing")
        XCTAssertFalse(app.buttons["strip.undo"].isEnabled, "Undo needs a shot")
        XCTAssertFalse(app.buttons["strip.generate"].exists && app.buttons["strip.generate"].isEnabled, "Generate waits for a slot")
        XCTAssertFalse(app.buttons["camera.lastPhoto"].exists, "The Roll thumbnail gives way to Generate")
        saveScreenshot(named: "camera-filmstrip")

        photo.tap()
        XCTAssertTrue(waitUntilSelected(photo))
        XCTAssertFalse(app.staticTexts["strip.count"].exists, "The strip layer is only in Film strip mode")

        // The camera's stock persists and gallery picks in other tests take
        // it (OPEN: v4-12): leave the simulator on Off
        for _ in 0..<5 where app.buttons["camera.dial.none"].frame.minX < 0 { dial.swipeRight() }
        app.buttons["camera.dial.none"].tap()
        XCTAssertTrue(waitUntilSelected(app.buttons["camera.dial.none"]))
    }

    @MainActor
    func testWhiteBalanceAndExposureOpenGlassSheets() throws {
        let app = launch()
        let wb = app.buttons["camera.wb.chip"]
        let ev = app.buttons["camera.ev.chip"]
        XCTAssertTrue(wb.waitForExistence(timeout: timeout))
        XCTAssertEqual(wb.value as? String, "AUTO", "White balance starts on Auto")
        XCTAssertEqual(ev.value as? String, "0.0", "Exposure starts at zero")

        wb.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForExistence(timeout: timeout), "Kelvin slider missing")
        XCTAssertTrue(app.sliders["camera.wb.tint"].exists, "Tint slider missing")
        for preset in ["auto", "sunlight", "cloudy", "shade", "tungsten", "fluorescent"] {
            XCTAssertTrue(app.buttons["camera.wb.\(preset)"].exists, "Preset \(preset) missing")
        }
        XCTAssertTrue(app.buttons["camera.wb.auto"].isSelected, "Auto is the active preset")
        saveScreenshot(named: "camera-wb-sheet")

        // A preset sets the button's value to its Kelvin
        app.buttons["camera.wb.tungsten"].tap()
        XCTAssertTrue(waitForValue(wb) { $0.hasSuffix("K") }, "A preset shows its Kelvin")
        XCTAssertTrue(app.buttons["camera.wb.tungsten"].isSelected)

        // A slider leaves no preset selected
        app.sliders["camera.wb.kelvin"].adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(waitForValue(wb) { $0.hasSuffix("K") && $0 != "AUTO" })
        XCTAssertFalse(app.buttons["camera.wb.tungsten"].isSelected, "A slider-set balance has no preset")
        saveScreenshot(named: "camera-wb-sheet-custom")

        // One sheet at a time: EV swaps into the same sheet
        ev.tap()
        XCTAssertTrue(app.sliders["camera.ev.slider"].waitForExistence(timeout: timeout), "EV slider missing: \(app.debugDescription.prefix(3000))")
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForNonExistence(timeout: timeout), "WB should give way when EV opens")
        app.buttons["camera.ev.brighter"].tap()
        XCTAssertTrue(waitForValue(ev) { $0 == "+0.3" }, "One step brighter reads +0.3")
        app.buttons["camera.ev.darker"].tap()
        app.buttons["camera.ev.darker"].tap()
        XCTAssertTrue(waitForValue(ev) { $0 == "-0.3" }, "Two steps darker reads -0.3, got \(String(describing: ev.value))")
        saveScreenshot(named: "camera-ev-sheet")

        // Tapping the open sheet's button again closes it
        ev.tap()
        XCTAssertTrue(app.sliders["camera.ev.slider"].waitForNonExistence(timeout: timeout), "The button closes its sheet")
        wb.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForExistence(timeout: timeout))
        wb.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForNonExistence(timeout: timeout))
    }

    // MARK: F2, F3, F8 editor

    @MainActor
    func testEditorToolbarScrubberCompareAndDownload() throws {
        let app = launch(arguments: [editArgument])
        XCTAssertTrue(app.buttons["edit.save"].waitForExistence(timeout: timeout), "Edit step did not open")
        let discard = app.buttons["edit.discard"]
        let retake = app.buttons["edit.retake"]
        let download = app.buttons["edit.download"]
        let diary = app.buttons["edit.continueDiary"]
        let save = app.buttons["edit.save"]

        // F2: icon buttons on glass, top bar
        XCTAssertTrue(retake.exists && download.exists && discard.exists)
        XCTAssertEqual([discard.label, retake.label, download.label], ["Discard", "Retake", "Download photo"])
        XCTAssertFalse(app.buttons["edit.delete"].exists, "Delete is for Roll photos only")
        XCTAssertLessThan(discard.frame.midX, retake.frame.midX, "Discard, then Retake, on the left")
        XCTAssertLessThan(retake.frame.midX, app.frame.midX)
        XCTAssertGreaterThan(download.frame.midX, app.frame.midX, "Download sits top right")
        // F3: Continue to diary (secondary) beside Save to roll (primary)
        XCTAssertTrue(diary.exists, "Continue to diary is offered right after a capture")
        XCTAssertLessThan(diary.frame.midX, save.frame.midX)
        XCTAssertEqual(save.label, "Save to roll")

        // F8: all seven tools in the icon bar, Film first and selected
        for id in toolIDs {
            XCTAssertTrue(app.buttons["edit.tool.\(id)"].exists, "Tool \(id) missing")
        }
        XCTAssertTrue(app.buttons["edit.tool.film"].isSelected)
        for id in stockIDs {
            XCTAssertTrue(app.buttons["edit.stock.\(id)"].exists, "Stock chip \(id) missing")
        }
        XCTAssertTrue(app.buttons["edit.stock.portrait400"].isSelected)
        let photoFrame = app.descendants(matching: .any)["edit.photo"].frame
        XCTAssertGreaterThan(photoFrame.height, app.frame.height * 0.5, "The photo takes most of the screen")
        saveScreenshot(named: "edit-tool-film")
        app.buttons["edit.stock.cine500T"].tap()
        XCTAssertTrue(app.buttons["edit.stock.cine500T"].isSelected)

        // Print: prints for a stock that has a choice, plus B&W
        app.buttons["edit.tool.print"].tap()
        XCTAssertTrue(app.switches["edit.blackAndWhite"].waitForExistence(timeout: timeout))
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'edit.print.'")).count, 0, "Print chips expected for Cine 500T")
        saveScreenshot(named: "edit-tool-print")
        app.buttons["edit.tool.film"].tap()
        app.buttons["edit.stock.mono400"].tap()
        app.buttons["edit.tool.print"].tap()
        XCTAssertFalse(app.switches["edit.blackAndWhite"].isEnabled, "A mono film is always black and white")
        app.buttons["edit.tool.film"].tap()
        app.buttons["edit.stock.portrait400"].tap()

        // One scrubber serves all five effects (0–150%, default 100%)
        let scrubber = app.descendants(matching: .any)["edit.scrubber"]
        let reset = app.buttons["edit.scrubber.reset"]
        app.buttons["edit.tool.halation"].tap()
        XCTAssertTrue(scrubber.waitForExistence(timeout: timeout), "Scrubber missing")
        XCTAssertEqual(scrubber.value as? String, "100%", "Halation starts at the stock default")
        XCTAssertFalse(reset.isEnabled, "Reset is off while the value is the default")
        saveScreenshot(named: "edit-tool-halation")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 == "0%" }, "The left end reads 0%, got \(String(describing: scrubber.value))")
        XCTAssertTrue(waitUntilEnabled(reset), "Reset enables once the value moves")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 == "150%" }, "The right end reads 150%, got \(String(describing: scrubber.value))")
        saveScreenshot(named: "edit-scrubber-150")
        reset.tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 == "100%" }, "Reset returns to the stock default")
        // Double-tap resets too
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 != "100%" })
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).doubleTap()
        XCTAssertTrue(waitForValue(scrubber) { $0 == "100%" }, "Double-tap resets to the default")

        // Switching tools swaps the effect the scrubber adjusts
        for effect in effectIDs.dropFirst() {
            app.buttons["edit.tool.\(effect)"].tap()
            XCTAssertTrue(waitForValue(scrubber) { $0.hasSuffix("%") })
            XCTAssertTrue(scrubber.label.count > 0)
            saveScreenshot(named: "edit-tool-\(effect)", settle: 0)
        }
        app.buttons["edit.tool.vignette"].tap()
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 != "0%" })
        saveScreenshot(named: "edit-vignette-changed")

        // Hold to compare: the photo reports "Original" while held. The press
        // blocks this thread, so the check runs from a background queue.
        let photo = app.descendants(matching: .any)["edit.photo"]
        let held = expectation(description: "photo reports Original while held")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            if (photo.value as? String) == "Original" { held.fulfill() }
        }
        photo.press(forDuration: 1.5)
        wait(for: [held], timeout: timeout)
        XCTAssertTrue(waitForValue(photo) { $0 == "With film look" }, "Releasing the photo restores the look")

        // Download: waits for the render, then confirms with Saved
        XCTAssertTrue(waitUntilEnabled(download), "Download stayed disabled")
        download.tap()
        // "Saved" shows for about 1.5 s, so poll the cheap badge element hard
        let badge = app.staticTexts["edit.saved"]
        var samples: [String] = []
        let deadline = Date().addingTimeInterval(15)
        var sawSaved = false
        while Date() < deadline && !sawSaved {
            let value = (download.value as? String) ?? "nil"
            samples.append(value)
            sawSaved = value == "Saved" || badge.exists
        }
        XCTAssertTrue(sawSaved, "Download never showed Saved; values seen: \(samples)")
        saveScreenshot(named: "edit-download-saved", settle: 0)

        // Retake leaves nothing behind and returns to the camera
        retake.tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Retake should return to the camera")
        XCTAssertFalse(save.exists)
    }

    // MARK: Save, re-edit, delete

    @MainActor
    func testSaveToRollThenReEditAndDelete() throws {
        let app = launch(arguments: [editArgument])
        XCTAssertTrue(app.buttons["edit.save"].waitForExistence(timeout: timeout))

        // Discard leaves nothing: count the Roll before and after
        app.buttons["edit.discard"].tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout))
        let before = rollCount(in: app)

        // Save to roll adds exactly one photo
        let relaunched = launch(arguments: [editArgument], terminating: app)
        XCTAssertTrue(relaunched.buttons["edit.save"].waitForExistence(timeout: timeout))
        relaunched.buttons["edit.save"].tap()
        XCTAssertTrue(relaunched.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Save should return to the camera")
        XCTAssertTrue(relaunched.buttons["camera.lastPhoto"].waitForExistence(timeout: timeout), "The last photo shows beside the shutter")
        saveScreenshot(named: "camera-photo-last-thumbnail")
        let afterSave = rollCount(in: relaunched)
        XCTAssertEqual(afterSave, before + 1, "Save to roll adds one photo (a discarded one adds none)")
        saveScreenshot(named: "library-roll-grid")

        // Re-edit: Delete (not Retake), Save (not Save to roll), no Continue to
        // diary (v5.1-2); Discard leaves it unchanged
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.delete"].waitForExistence(timeout: timeout), "Re-edit offers Delete")
        XCTAssertFalse(relaunched.buttons["edit.retake"].exists)
        XCTAssertFalse(relaunched.buttons["edit.continueDiary"].exists, "Continue to diary is only right after a capture")
        XCTAssertEqual(relaunched.buttons["edit.save"].label, "Save")
        saveScreenshot(named: "edit-reedit")
        relaunched.buttons["edit.tool.vignette"].tap()
        let scrubber = relaunched.descendants(matching: .any)["edit.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: timeout))
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        relaunched.buttons["edit.discard"].tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForExistence(timeout: timeout))
        XCTAssertEqual(rollCount(in: relaunched), afterSave, "Discard in re-edit keeps the photo")

        // Save in re-edit updates and returns to the Roll
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.save"].waitForExistence(timeout: timeout))
        relaunched.buttons["edit.tool.vignette"].tap()
        XCTAssertEqual(scrubber.value as? String, "0%", "Discarded changes must not have been saved")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        relaunched.buttons["edit.save"].tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForExistence(timeout: timeout))
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.save"].waitForExistence(timeout: timeout))
        relaunched.buttons["edit.tool.vignette"].tap()
        XCTAssertNotEqual(scrubber.value as? String, "0%", "Saved vignette should persist")

        // Delete asks first; a photo with no entry gets the plain confirmation
        relaunched.buttons["edit.delete"].tap()
        XCTAssertTrue(relaunched.buttons["edit.delete.confirm"].waitForExistence(timeout: timeout), "Delete needs a confirmation")
        XCTAssertFalse(relaunched.buttons["edit.delete.keepEntry"].exists, "No entry, no entry question")
        saveScreenshot(named: "edit-delete-confirm")
        relaunched.buttons["edit.delete.confirm"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForNonExistence(timeout: 2) || rollCount(in: relaunched) == before, "Delete removes the photo")
        XCTAssertEqual(rollCount(in: relaunched), before)
    }

    // MARK: Roll → Make strip (the strip screen's own controls are in StripScreenUITests)

    @MainActor
    func testRollSelectAndMakeStrip() throws {
        let app = launch(arguments: [seedArgument])
        openRoll(app)
        let cells = app.buttons.matching(identifier: "roll.photo")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: timeout), "Seeded Roll is empty")
        XCTAssertGreaterThanOrEqual(cells.count, 3)
        saveScreenshot(named: "library-roll-seeded", settle: 2)

        // Select mode: numbered selection, at most four photos
        app.buttons["roll.select"].tap()
        XCTAssertTrue(app.buttons["roll.makeStrip"].waitForExistence(timeout: timeout), "The selection bar did not appear")
        XCTAssertFalse(app.buttons["roll.makeStrip"].isEnabled, "Make strip needs a selection")
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["roll.selectionSummary"].label.contains("2 selected"), app.staticTexts["roll.selectionSummary"].label)
        XCTAssertTrue(app.buttons["roll.export"].isEnabled)
        saveScreenshot(named: "library-roll-select", settle: 1)
        cells.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["roll.selectionSummary"].label.contains("1 selected"))
        cells.element(boundBy: 0).tap()

        // Make strip opens the strip screen with the effect tools (F10)
        app.buttons["roll.makeStrip"].tap()
        XCTAssertTrue(app.buttons["strip.tool.film"].waitForExistence(timeout: timeout), "Strip screen did not open")
        for effect in effectIDs {
            XCTAssertTrue(app.buttons["strip.tool.\(effect)"].exists, "\(effect) tool missing on the strip screen")
        }
        app.buttons["strip.tool.halation"].tap()
        let halation = app.descendants(matching: .any)["strip.scrubber"]
        XCTAssertTrue(halation.waitForExistence(timeout: timeout))
        XCTAssertEqual(halation.value as? String, "100%", "Strip halation defaults to the stock default")
        halation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(halation) { $0 != "100%" }, "Halation scrubber did not move: \(String(describing: halation.value))")
        saveScreenshot(named: "strip-screen-roll-halation", settle: 2)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["roll.select"].waitForExistence(timeout: timeout), "Close returns to the Roll")
    }

    // MARK: Steps

    @MainActor
    private func launch(arguments: [String] = [], terminating previous: XCUIApplication? = nil) -> XCUIApplication {
        previous?.terminate()
        let app = XCUIApplication()
        app.launchArguments = arguments + appearanceArguments
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Allow Full Access"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        dismissInAppOverlays(app)
        return app
    }

    // TEST_RUNNER_SHOTS_SUFFIX=dark renders the light-and-dark screens dark
    private var appearanceArguments: [String] {
        ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] == "dark" ? ["-AppleInterfaceStyle", "Dark"] : []
    }

    // The simulator has no camera, so an alert (OK) comes first; the
    // first-run walkthrough (Skip) follows once it is answered
    private func dismissInAppOverlays(_ app: XCUIApplication) {
        app.tap()
        for _ in 0..<2 {
            for label in ["OK", "Skip"] {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 3) { button.tap() }
            }
        }
    }

    private func openRoll(_ app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
        let roll = app.buttons["library.tab.roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: timeout))
        roll.tap()
    }

    // How many photos the Roll holds; leaves the Library's Roll tab open
    private func rollCount(in app: XCUIApplication) -> Int {
        openRoll(app)
        _ = app.buttons["roll.photo"].waitForExistence(timeout: 2)
        return app.buttons.matching(identifier: "roll.photo").count
    }

    private func waitUntilSelected(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isSelected == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitUntilNotSelected(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isSelected == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitForValue(_ element: XCUIElement, matching check: @escaping (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = element.value as? String, check(value) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func saveScreenshot(named name: String, settle: UInt32 = 1) {
        if settle > 0 { sleep(settle) }
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            let suffix = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"].map { "-\($0)" } ?? ""
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)\(suffix).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
