import XCTest

// v5 UI: Photo mode chrome (F1–F3), the edit step (F4), sliders (F5) and the
// Roll (F6). The simulator has no camera, so the edit step is reached through
// the DEBUG-only `-UITestPhotoEdit` launch argument (a generated photo whose
// Download writes nowhere; Save to roll really saves), and a Roll with photos
// through `-UITestSeedRoll` (three generated photos added per launch).
// Real capture, the camera-roll save, export, haptics and rotation are
// device-only.
// Optional: TEST_RUNNER_SHOTS_DIR=<abs dir> writes the screenshots there.
final class PhotoModeUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    private let editArgument = "-UITestPhotoEdit"
    private let seedArgument = "-UITestSeedRoll"
    private let stockIDs = ["none", "daylight200", "portrait400", "cine500T", "slide100", "mono400", "mono3200"]
    private let effectIDs = ["halation", "haze", "lightLeak", "grain", "vignette"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: F1–F3 camera chrome

    @MainActor
    func testPhotoModeIsTheLaunchModeWithItsChrome() throws {
        let app = launch()

        // F1: three-way switch, Photo first and selected
        let photo = app.buttons["camera.mode.photo"]
        let diary = app.buttons["camera.mode.diary"]
        let strip = app.buttons["camera.mode.filmstrip"]
        XCTAssertTrue(photo.waitForExistence(timeout: timeout), "Photo mode button missing")
        XCTAssertEqual([photo.label, diary.label, strip.label], ["Photo", "Diary", "Film strip"])
        XCTAssertLessThan(photo.frame.midX, diary.frame.midX)
        XCTAssertLessThan(diary.frame.midX, strip.frame.midX)
        XCTAssertTrue(photo.isSelected, "The app opens in Photo mode")
        XCTAssertFalse(strip.isSelected, "Film strip must not be highlighted in Photo mode")

        // F2: the dial shows every stock, the Film chip is not used
        for id in stockIDs {
            XCTAssertTrue(app.buttons["camera.dial.\(id)"].exists, "Dial detent \(id) missing")
        }
        XCTAssertFalse(app.buttons["camera.film.none"].exists, "Photo mode replaces the Film chip with the dial")
        saveScreenshot(named: "camera-photo-collapsed")

        // Tapping a detent selects that stock
        let target = app.buttons["camera.dial.cine500T"]
        target.tap()
        XCTAssertTrue(waitUntilSelected(target), "Tapping a detent selects it")
        saveScreenshot(named: "camera-photo-dial-cine500T")

        // Swiping the dial moves to a neighbour
        let dial = app.descendants(matching: .any)["camera.dial"]
        dial.swipeLeft(velocity: .slow)
        XCTAssertTrue(waitUntilNotSelected(target), "Swiping the dial leaves the previous stock")
        let selectedCount = stockIDs.filter { app.buttons["camera.dial.\($0)"].isSelected }.count
        XCTAssertEqual(selectedCount, 1, "Exactly one stock is selected")

        // Diary and Film strip keep the Film chip (v5-2), and Photo brings the dial back
        diary.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'camera.film.'")).firstMatch.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["camera.dial.none"].exists)
        saveScreenshot(named: "camera-diary-chip")
        photo.tap()
        XCTAssertTrue(app.buttons["camera.dial.none"].waitForExistence(timeout: timeout))

        // The camera's stock persists and gallery picks in other tests take
        // it (OPEN: v4-12): leave the simulator on Off
        for _ in 0..<5 where app.buttons["camera.dial.none"].frame.minX < 0 { dial.swipeRight() }
        app.buttons["camera.dial.none"].tap()
        XCTAssertTrue(waitUntilSelected(app.buttons["camera.dial.none"]))
    }

    @MainActor
    func testWhiteBalanceAndExposurePanelsAreExclusive() throws {
        let app = launch()
        let wbChip = app.buttons["camera.wb.chip"]
        let evChip = app.buttons["camera.ev.chip"]
        XCTAssertTrue(wbChip.waitForExistence(timeout: timeout))
        XCTAssertEqual(wbChip.value as? String, "AUTO", "White balance starts on Auto")
        XCTAssertEqual(evChip.value as? String, "0.0", "Exposure starts at zero")

        wbChip.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForExistence(timeout: timeout), "Kelvin slider missing")
        XCTAssertTrue(app.sliders["camera.wb.tint"].exists, "Tint slider missing")
        for preset in ["auto", "sunlight", "cloudy", "shade", "tungsten", "fluorescent"] {
            XCTAssertTrue(app.buttons["camera.wb.\(preset)"].exists, "Preset \(preset) missing")
        }
        XCTAssertTrue(app.buttons["camera.wb.auto"].isSelected, "Auto is the active preset")
        saveScreenshot(named: "camera-photo-wb-panel")

        // A preset sets the chip to its Kelvin
        app.buttons["camera.wb.tungsten"].tap()
        XCTAssertTrue(waitForValue(wbChip) { $0.hasSuffix("K") }, "A preset shows its Kelvin on the chip")
        XCTAssertTrue(app.buttons["camera.wb.tungsten"].isSelected)

        // A slider leaves no preset selected
        app.sliders["camera.wb.kelvin"].adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertTrue(waitForValue(wbChip) { $0.hasSuffix("K") && $0 != "AUTO" })
        XCTAssertFalse(app.buttons["camera.wb.tungsten"].isSelected, "A slider-set balance has no preset")
        saveScreenshot(named: "camera-photo-wb-custom")

        // Only one panel at a time
        evChip.tap()
        XCTAssertTrue(app.sliders["camera.ev.slider"].waitForExistence(timeout: timeout), "EV slider missing")
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForNonExistence(timeout: timeout), "WB panel should close when EV opens")
        app.buttons["camera.ev.brighter"].tap()
        XCTAssertTrue(waitForValue(evChip) { $0 == "+0.3" }, "One step brighter reads +0.3")
        app.buttons["camera.ev.darker"].tap()
        app.buttons["camera.ev.darker"].tap()
        XCTAssertTrue(waitForValue(evChip) { $0 == "-0.3" }, "Two steps darker reads -0.3, got \(String(describing: evChip.value))")
        saveScreenshot(named: "camera-photo-ev-panel")

        wbChip.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.sliders["camera.ev.slider"].waitForNonExistence(timeout: timeout), "EV panel should close when WB opens")

        // Tapping the chip again closes the panel
        wbChip.tap()
        XCTAssertTrue(app.sliders["camera.wb.kelvin"].waitForNonExistence(timeout: timeout))
    }

    // MARK: F4 edit step

    @MainActor
    func testEditStepTabsSlidersCompareAndDownload() throws {
        let app = launch(arguments: [editArgument])
        XCTAssertTrue(app.buttons["edit.save"].waitForExistence(timeout: timeout), "Edit step did not open")
        let retake = app.buttons["edit.retake"]
        let download = app.buttons["edit.download"]
        let discard = app.buttons["edit.discard"]
        let save = app.buttons["edit.save"]
        XCTAssertTrue(retake.exists && download.exists && discard.exists)
        XCTAssertFalse(app.buttons["edit.delete"].exists, "Delete is for Roll photos only")
        XCTAssertLessThan(retake.frame.midX, app.frame.midX, "Retake sits top left")
        XCTAssertGreaterThan(download.frame.midX, app.frame.midX, "Download sits top right")
        XCTAssertLessThan(discard.frame.midX, save.frame.midX, "Discard left, Save to roll right")
        XCTAssertEqual(save.label, "Save to roll")

        // Film tab: every stock, the capture's stock selected
        XCTAssertTrue(app.buttons["edit.tab.film"].isSelected)
        for id in stockIDs {
            XCTAssertTrue(app.buttons["edit.stock.\(id)"].exists, "Stock chip \(id) missing")
        }
        XCTAssertTrue(app.buttons["edit.stock.portrait400"].isSelected)
        saveScreenshot(named: "edit-film-tab")
        app.buttons["edit.stock.cine500T"].tap()
        XCTAssertTrue(app.buttons["edit.stock.cine500T"].isSelected)

        // Print tab: prints for a stock that has a choice, plus B&W
        app.buttons["edit.tab.print"].tap()
        XCTAssertTrue(app.switches["edit.blackAndWhite"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'edit.print.'")).count > 0, true, "Print chips expected for Cine 500T")
        saveScreenshot(named: "edit-print-tab")
        app.buttons["edit.tab.film"].tap()
        app.buttons["edit.stock.mono400"].tap()
        app.buttons["edit.tab.print"].tap()
        XCTAssertFalse(app.switches["edit.blackAndWhite"].isEnabled, "A mono film is always black and white")
        app.buttons["edit.tab.film"].tap()
        app.buttons["edit.stock.portrait400"].tap()

        // Effects tab: five percent sliders and Reset (v5-5)
        app.buttons["edit.tab.effects"].tap()
        for effect in effectIDs {
            XCTAssertTrue(app.sliders["edit.slider.\(effect)"].waitForExistence(timeout: timeout), "\(effect) slider missing")
        }
        let reset = app.buttons["edit.effects.reset"]
        XCTAssertFalse(reset.isEnabled, "Reset is off while the look is the stock's defaults")
        let halation = app.sliders["edit.slider.halation"]
        XCTAssertEqual(halation.value as? String, "100%")
        saveScreenshot(named: "edit-effects-tab")
        halation.adjust(toNormalizedSliderPosition: 0)
        XCTAssertTrue(waitForValue(halation) { $0 == "0%" }, "Halation should read 0%, got \(String(describing: halation.value))")
        let grain = app.sliders["edit.slider.grain"]
        grain.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(waitForValue(grain) { $0 == "150%" }, "Grain tops out at 150%, got \(String(describing: grain.value))")
        XCTAssertTrue(waitUntilEnabled(reset), "Reset enables once an effect changes")
        saveScreenshot(named: "edit-effects-changed")
        reset.tap()
        XCTAssertTrue(waitForValue(halation) { $0 == "100%" }, "Reset restores the stock's defaults")
        XCTAssertTrue(waitForValue(grain) { $0 == "100%" })

        // Hold to compare: the photo reports "Original" while held. The press
        // blocks this thread, so the check runs from a background queue.
        let photo = app.descendants(matching: .any)["edit.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: timeout), "Photo missing")
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
        let saved = NSPredicate(format: "value == 'Saved'")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: download)], timeout: timeout),
            .completed, "Download never showed Saved"
        )
        saveScreenshot(named: "edit-download-saved", settle: 0)

        // Retake leaves nothing behind and returns to the camera
        retake.tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Retake should return to the camera")
        XCTAssertFalse(save.exists)
    }

    // MARK: F4 + F6 save, re-edit, delete

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

        // Re-edit: Delete (not Retake), Save (not Save to roll); Discard leaves it unchanged
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.delete"].waitForExistence(timeout: timeout), "Re-edit offers Delete")
        XCTAssertFalse(relaunched.buttons["edit.retake"].exists)
        XCTAssertEqual(relaunched.buttons["edit.save"].label, "Save")
        saveScreenshot(named: "edit-reedit")
        relaunched.buttons["edit.tab.effects"].tap()
        relaunched.sliders["edit.slider.vignette"].adjust(toNormalizedSliderPosition: 0.7)
        relaunched.buttons["edit.discard"].tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForExistence(timeout: timeout))
        XCTAssertEqual(rollCount(in: relaunched), afterSave, "Discard in re-edit keeps the photo")

        // Save in re-edit updates and returns to the Roll
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.save"].waitForExistence(timeout: timeout))
        relaunched.buttons["edit.tab.effects"].tap()
        let vignette = relaunched.sliders["edit.slider.vignette"]
        XCTAssertEqual(vignette.value as? String, "0%", "Discarded changes must not have been saved")
        vignette.adjust(toNormalizedSliderPosition: 0.7)
        relaunched.buttons["edit.save"].tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForExistence(timeout: timeout))
        relaunched.buttons["roll.photo"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["edit.save"].waitForExistence(timeout: timeout))
        relaunched.buttons["edit.tab.effects"].tap()
        XCTAssertNotEqual(relaunched.sliders["edit.slider.vignette"].value as? String, "0%", "Saved vignette should persist")

        // Delete asks first
        relaunched.buttons["edit.delete"].tap()
        XCTAssertTrue(relaunched.buttons["edit.delete.confirm"].waitForExistence(timeout: timeout), "Delete needs a confirmation")
        saveScreenshot(named: "edit-delete-confirm")
        relaunched.buttons["edit.delete.confirm"].firstMatch.tap()
        XCTAssertTrue(relaunched.buttons["roll.photo"].waitForNonExistence(timeout: 2) || rollCount(in: relaunched) == before, "Delete removes the photo")
        XCTAssertEqual(rollCount(in: relaunched), before)
    }

    // MARK: F6 select, Make strip, strip sliders, Clear roll

    @MainActor
    func testRollSelectMakeStripThenClearRoll() throws {
        let app = launch(arguments: [seedArgument])
        openRoll(app)
        let cells = app.buttons.matching(identifier: "roll.photo")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: timeout), "Seeded Roll is empty")
        XCTAssertGreaterThanOrEqual(cells.count, 3)
        saveScreenshot(named: "library-roll-seeded", settle: 3)

        // Select mode: numbered selection, at most four photos
        app.buttons["roll.select"].tap()
        XCTAssertFalse(app.buttons["roll.makeStrip"].isEnabled, "Make strip needs a selection")
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["roll.selectionSummary"].label.contains("2 selected"), app.staticTexts["roll.selectionSummary"].label)
        XCTAssertTrue(app.buttons["roll.export"].isEnabled)
        saveScreenshot(named: "library-roll-select", settle: 2)
        cells.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["roll.selectionSummary"].label.contains("1 selected"))
        cells.element(boundBy: 0).tap()

        // Make strip opens the strip screen with effect sliders (F5)
        app.buttons["roll.makeStrip"].tap()
        XCTAssertTrue(app.buttons["strip.filmStock"].waitForExistence(timeout: timeout), "Strip screen did not open")
        for effect in effectIDs {
            XCTAssertTrue(app.sliders["strip.slider.\(effect)"].waitForExistence(timeout: timeout), "\(effect) slider missing on the strip screen")
        }
        let halation = app.sliders["strip.slider.halation"]
        XCTAssertEqual(halation.value as? String, "100%", "Strip halation defaults to the stock default")
        // The strip previews are tall: scroll the controls card into view
        for _ in 0..<5 where !halation.isHittable { app.swipeUp() }
        halation.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(waitForValue(halation) { $0 != "100%" }, "Halation slider did not move: \(String(describing: halation.value))")
        saveScreenshot(named: "strip-screen-sliders", settle: 3)
        app.buttons["Close"].tap()

        // Settings: sliders replace the toggles; Clear roll is separate
        app.tabBars.buttons["Settings"].tap()
        let stock = app.buttons["settings.filmStock"]
        XCTAssertTrue(stock.waitForExistence(timeout: timeout))
        app.swipeUp()
        for effect in effectIDs {
            XCTAssertTrue(app.sliders["settings.slider.\(effect)"].waitForExistence(timeout: timeout), "\(effect) slider missing in Settings")
        }
        XCTAssertFalse(app.switches["settings.halation"].exists, "Toggles are gone")
        XCTAssertFalse(app.switches["Remember white balance"].exists, "Remember white balance was removed (v5-4)")
        saveScreenshot(named: "settings-sliders", settle: 2)
        app.swipeUp()
        let clearRoll = app.buttons["settings.clearRoll"]
        XCTAssertTrue(clearRoll.waitForExistence(timeout: timeout), "Clear roll missing")
        clearRoll.tap()
        XCTAssertTrue(app.buttons["settings.clearRoll.confirm"].waitForExistence(timeout: timeout), "Clear roll needs a confirmation")
        saveScreenshot(named: "settings-clear-roll-confirm", settle: 1)
        app.buttons["settings.clearRoll.confirm"].firstMatch.tap()

        // The Roll is empty and invites a shot
        openRoll(app)
        XCTAssertTrue(app.otherElements["roll.empty"].waitForExistence(timeout: timeout) || app.buttons["roll.takePhoto"].waitForExistence(timeout: timeout), "Empty Roll invitation missing")
        saveScreenshot(named: "library-roll-empty", settle: 2)
        app.buttons["roll.takePhoto"].tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "The invitation opens the camera")
    }

    // MARK: Steps

    @MainActor
    private func launch(arguments: [String] = [], terminating previous: XCUIApplication? = nil) -> XCUIApplication {
        previous?.terminate()
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
        dismissInAppOverlays(app)
        return app
    }

    private func dismissInAppOverlays(_ app: XCUIApplication) {
        app.tap()
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        let ok = app.buttons["OK"]
        if ok.waitForExistence(timeout: 1) { ok.tap() }
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
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
