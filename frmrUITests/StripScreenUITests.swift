import XCTest

// v4 F7 (BUG-V4-3), Part 2 F8/F12, v5.1 F9/F10: the Film strip camera layer
// (Pick from Roll, slots, Generate) and the strip screen with its glass
// sheet (tool icon bar, chips, scrubber). One test opens the strip screen
// through the photobooth gallery picker, checks the As shot default and the
// two papers, and cycles every stock choice, checking which tools show; the
// other fills the slots from a seeded Roll. Settings' strip defaults are
// covered by the Settings UI tests.
//
// SETUP (once per simulator, before running): the gallery test needs at
// least four photos in the photo library. From the project root:
//   xcrun simctl addmedia <udid> qa/fixtures/strip-fixture-*.png
// (scripts/test.sh ui does this for its shard simulators). Every launch
// passes `-UITestFast` (animations off). Optional: TEST_RUNNER_SHOTS_DIR=<abs
// dir> also writes screenshots there (SHOTS_SUFFIX=dark renders dark).
final class StripScreenUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    // Chip identifiers: As shot, then the seven stocks (StripCustomization raw values)
    private let asShot = "asShot"
    private let stocks = ["none", "daylight200", "portrait400", "cine500T", "slide100", "mono400", "mono3200"]
    private var stockChoices: [String] { [asShot] + stocks }
    private let stocksWithoutPrint: Set<String> = ["none", "slide100"]
    private let monoStocks: Set<String> = ["mono400", "mono3200"]
    private let effectIDs = ["halation", "haze", "lightLeak", "grain", "vignette"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The strip screen rotates; a simulator left in landscape pushes
        // content off screen, where it doesn't exist to query
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testStripScreenCyclesEveryStock() throws {
        let app = launch()

        let filmStripMode = app.buttons["camera.mode.filmstrip"]
        XCTAssertTrue(filmStripMode.waitForExistence(timeout: timeout), "Film strip mode switch missing")
        filmStripMode.tap()

        // v5.2 S2: the gallery lives in the mini-strip's sheet
        app.buttons["strip.miniStrip"].tap()
        let gallery = app.buttons["Choose photos from library"]
        XCTAssertTrue(gallery.waitForExistence(timeout: timeout), "The strip sheet did not open")
        gallery.tap()
        try pickFourPhotos(app)

        let generate = app.buttons["Generate strip"]
        XCTAssertTrue(generate.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntilEnabled(generate), "Generate stayed disabled; were 4 photos picked?")
        XCTAssertTrue(waitForLabel(app.staticTexts["strip.count"], "Captured 4 of 4"))
        saveScreenshot(named: "camera-filmstrip-4of4")
        generate.tap()

        XCTAssertTrue(app.buttons["strip.tool.film"].waitForExistence(timeout: timeout), "Strip screen did not open")
        // v5.2 S3 / v5.2-7: one primary, Keep strip; Share and Download are icons
        let keep = app.buttons["strip.keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: timeout), "Keep strip missing")
        XCTAssertTrue(app.buttons["strip.share"].exists && app.buttons["strip.download"].exists, "Share and Download are icons at the top")
        XCTAssertFalse(app.buttons["strip.save"].exists || app.buttons["strip.archive"].exists, "Save and Archive merged into Keep strip")
        XCTAssertLessThan(app.buttons["strip.close"].frame.maxY, app.images["strip.preview"].firstMatch.frame.minY + 1, "Close never covers the strip")
        XCTAssertLessThanOrEqual(keep.frame.maxY, app.frame.maxY, "Keep strip is on screen")
        for id in ["strip.close", "strip.share", "strip.download", "strip.keep"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44, "\(id) is below 44 pt")
        }

        // F8: Paper is the first tool: exactly two swatches, white selected
        XCTAssertTrue(app.buttons["strip.tool.paper"].isSelected, "The sheet opens on Paper")
        let white = app.buttons["strip.background.white"]
        let black = app.buttons["strip.background.black"]
        XCTAssertTrue(white.exists && black.exists, "White and Black swatches expected")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.background.'")).count, 2)
        XCTAssertTrue(white.isSelected, "White should be the default background")
        black.tap()
        XCTAssertTrue(black.isSelected, "Black swatch should select")
        saveScreenshot(named: "strip-screen-asShot-black")
        white.tap()
        XCTAssertTrue(white.isSelected, "White swatch should select")
        saveScreenshot(named: "strip-screen-asShot-white")

        // F12: a new strip starts As shot; the Film tool offers As shot + 7 stocks
        app.buttons["strip.tool.film"].tap()
        for choice in stockChoices {
            XCTAssertTrue(app.buttons["strip.stock.\(choice)"].waitForExistence(timeout: timeout), "Stock chip \(choice) missing")
        }
        XCTAssertTrue(app.buttons["strip.stock.\(asShot)"].isSelected, "Default stock should be As shot")
        assertTools(for: asShot, app: app)
        saveScreenshot(named: "strip-screen-film-asShot")

        for choice in stocks + [asShot] {
            select(choice, app: app)
            assertTools(for: choice, app: app)
        }

        select("cine500T", app: app)
        saveScreenshot(named: "strip-screen-film-cine500T")
        app.buttons["strip.tool.print"].tap()
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strip.print.'")).count, 0, "Print chips expected for Cine 500T")
        saveScreenshot(named: "strip-screen-print")
        app.buttons["strip.tool.grain"].tap()
        let scrubber = app.descendants(matching: .any)["strip.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: timeout))
        XCTAssertEqual(scrubber.value as? String, "100%")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        XCTAssertTrue(waitForValue(scrubber) { $0 == "150%" }, "Grain scrubber should reach 150%")
        saveScreenshot(named: "strip-screen-grain-150")
        app.buttons["strip.tool.film"].tap()
        select("mono400", app: app)
        saveScreenshot(named: "strip-screen-film-mono400")

        // v4 F15: archive a black-paper strip and check the Library and the
        // detail viewer show it at its own (taller, 4:5-frame) aspect.
        // Adds one strip to the simulator's library.
        select(asShot, app: app)
        app.buttons["strip.tool.paper"].tap()
        black.tap()
        keep.tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: timeout), "Keep strip should close the strip screen")
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["Strips"].tap()
        let archived = app.buttons.matching(identifier: "library.strip").firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: timeout), "Archived strip missing from Library")
        saveScreenshot(named: "library-strips-booth")
        archived.tap()
        saveScreenshot(named: "strip-detail-booth")
    }

    // v5.1 F9: Pick from Roll fills the slots (no photo library needed), the
    // count follows, Generate appears with the first slot, and Close clears
    @MainActor
    func testPickFromRollFillsSlotsThenGenerate() throws {
        let app = launch(arguments: ["-UITestSeedRoll"])
        let strip = app.buttons["camera.mode.filmstrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: timeout))
        strip.tap()
        let miniStrip = app.buttons["strip.miniStrip"]
        XCTAssertTrue(miniStrip.waitForExistence(timeout: timeout))
        XCTAssertTrue(miniStrip.label.contains("0 of 4"), miniStrip.label)
        miniStrip.tap()
        let count = app.staticTexts["strip.count"]
        XCTAssertTrue(count.waitForExistence(timeout: timeout))
        XCTAssertEqual(count.label, "Captured 0 of 4")

        app.buttons["strip.pickRoll"].tap()
        let cells = app.buttons.matching(identifier: "strip.rollPicker.photo")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: timeout), "The Roll picker shows no photos")
        saveScreenshot(named: "camera-filmstrip-roll-picker", settle: 2)
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        app.buttons["strip.rollPicker.done"].tap()
        XCTAssertTrue(waitForLabel(count, "Captured 2 of 4"), "Two picks fill two slots, got \(count.label)")

        let generate = app.buttons["Generate strip"]
        XCTAssertTrue(generate.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntilEnabled(generate), "Generate enables once a slot is filled")
        XCTAssertTrue(app.buttons["strip.undo"].isEnabled)
        saveScreenshot(named: "camera-filmstrip-2of4")
        app.buttons["strip.undo"].tap()
        XCTAssertTrue(waitForLabel(count, "Captured 1 of 4"), "Undo empties the last slot")
        app.buttons["strip.pickRoll"].tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: timeout))
        cells.element(boundBy: 2).tap()
        app.buttons["strip.rollPicker.done"].tap()
        XCTAssertTrue(waitForLabel(count, "Captured 2 of 4"))

        generate.tap()
        XCTAssertTrue(app.buttons["strip.tool.film"].waitForExistence(timeout: timeout), "Strip screen did not open")
        saveScreenshot(named: "strip-screen-paper", settle: 2)
        app.buttons["strip.tool.halation"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["strip.scrubber"].waitForExistence(timeout: timeout))
        saveScreenshot(named: "strip-screen-halation", settle: 2)
        app.buttons["strip.tool.film"].tap()
        saveScreenshot(named: "strip-screen-film", settle: 1)
        app.buttons["strip.close"].tap()
        XCTAssertTrue(miniStrip.waitForExistence(timeout: timeout), "Close returns to the camera")
        XCTAssertTrue(miniStrip.label.contains("0 of 4"), "Closing the strip clears the slots: \(miniStrip.label)")
    }

    // MARK: Steps

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let dark = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] == "dark"
        app.launchArguments = ["-UITestFast"] + arguments + (dark ? ["-AppleInterfaceStyle", "Dark"] : [])
        // Camera and photo-library permission prompts are springboard alerts
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow Full Access", "Allow", "OK", "Continue"] where alert.buttons[label].exists {
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
        // Nudge the interruption monitor, then clear the simulator's
        // "no camera" alert and the first-run walkthrough
        app.tap()
        for _ in 0..<2 {
            for label in ["OK", "Skip"] {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 3) { button.tap() }
            }
        }
    }

    // PhotosPicker runs out of process but its grid shows up in the app's
    // accessibility tree: each cell is an Image with this identifier. The
    // cells report not hittable (a dimming overlay sits above them), so tap
    // by coordinate.
    private func pickFourPhotos(_ app: XCUIApplication) throws {
        let photos = app.images.matching(identifier: "PXGGridLayout-Info")
        guard photos.firstMatch.waitForExistence(timeout: timeout) else {
            throw XCTSkip("PhotosPicker grid not reachable — is the library seeded (see file header)?")
        }
        guard photos.count >= 4 else {
            throw XCTSkip("Library has \(photos.count) photos; run the addmedia setup step")
        }
        for index in 0..<4 {
            photos.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let done = app.buttons["Done"]
        XCTAssertTrue(waitUntilEnabled(done), "Picker Done stayed disabled")
        done.tap()
    }

    // Tapping a stock chip also brings it into view in the scrolling row
    private func select(_ stock: String, app: XCUIApplication) {
        let chip = app.buttons["strip.stock.\(stock)"]
        XCTAssertTrue(chip.waitForExistence(timeout: timeout), "Stock chip \(stock) missing")
        let row = app.scrollViews.containing(.button, identifier: "strip.stock.\(asShot)").firstMatch
        // isHittable throws for an off-screen chip, so compare frames
        for _ in 0..<stockChoices.count where chip.frame.maxX > app.frame.maxX { row.swipeLeft() }
        for _ in 0..<stockChoices.count where chip.frame.minX < 0 { row.swipeRight() }
        chip.tap()
        XCTAssertTrue(waitUntilSelected(chip), "\(stock): chip did not select")
    }

    // As shot shows no print tool. Gallery picks take the camera's stock
    // (default Off, OPEN v4-10/v4-12), so under As shot every frame is Off
    // and the effect tools are hidden too (F12: hidden only when every
    // effective stock is Off). B&W is locked on for mono stocks.
    private func assertTools(for stock: String, app: XCUIApplication) {
        XCTAssertTrue(app.buttons["strip.tool.bw"].waitForExistence(timeout: timeout), "\(stock): B&W tool missing")
        let print = app.buttons["strip.tool.print"]
        // Let the row settle before checking absence
        _ = print.waitForNonExistence(timeout: stocksWithoutPrint.contains(stock) || stock == asShot ? 1 : 0.1)
        let effectsExpected = stock != "none" && stock != asShot
        XCTAssertEqual(print.exists, !stocksWithoutPrint.contains(stock) && stock != asShot, "\(stock): print tool visibility")
        for effect in effectIDs {
            XCTAssertEqual(app.buttons["strip.tool.\(effect)"].exists, effectsExpected, "\(stock): \(effect) tool visibility")
        }
        app.buttons["strip.tool.bw"].tap()
        let blackAndWhite = app.switches["strip.blackAndWhite"]
        XCTAssertTrue(blackAndWhite.waitForExistence(timeout: timeout), "\(stock): B&W toggle missing")
        XCTAssertEqual(blackAndWhite.isEnabled, !monoStocks.contains(stock), "\(stock): B&W lock")
        if monoStocks.contains(stock) {
            XCTAssertEqual(blackAndWhite.value as? String, "1", "\(stock): B&W should read on")
        }
        XCTAssertTrue(app.buttons["strip.keep"].exists, "\(stock): Keep strip missing")
        app.buttons["strip.tool.film"].tap()
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntilSelected(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isSelected == true")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
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

    private func saveScreenshot(named name: String, settle: UInt32 = 2) {
        // Give the re-render a moment so the strip reflects the stock
        sleep(settle)
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
