import XCTest

// v4 F7 (BUG-V4-3; v5 F5: effect sliders), Part 2 F8/F12: opens the strip screen through the
// photobooth gallery picker, checks the As shot default and the two
// backgrounds, and cycles every stock choice, checking which controls show.
//
// SETUP (once per simulator, before running): the photo library needs at
// least four photos. From the project root:
//   xcrun simctl addmedia <udid> qa/fixtures/strip-fixture-*.png
// Optional: TEST_RUNNER_SHOTS_DIR=<abs dir> on the xcodebuild command line
// also writes a strip-screen screenshot there (the XCTAttachment is always kept).
final class StripScreenUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    // Labels mirror StripCustomization.label(forStockChoice:): As shot,
    // then the seven stocks
    private let asShot = "As shot"
    private let stocks = ["Off", "Daylight 200", "Portrait 400", "Cine 500T", "Slide 100", "Mono 400", "Mono 3200"]
    private var stockChoices: [String] { [asShot] + stocks }
    private let stocksWithoutPrint: Set<String> = ["Off", "Slide 100"]
    private let monoStocks: Set<String> = ["Mono 400", "Mono 3200"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Settings and the strip screen rotate; a simulator left in landscape
        // pushes lazy List rows off screen, where they don't exist to query
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testStripScreenCyclesEveryStock() throws {
        let app = XCUIApplication()
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

        let filmStripMode = app.buttons["Film strip"]
        XCTAssertTrue(filmStripMode.waitForExistence(timeout: timeout), "Film strip mode toggle missing")
        filmStripMode.tap()
        dismissInAppOverlays(app)

        app.buttons["Choose photos from library"].tap()
        try pickFourPhotos(app)

        let generate = app.buttons["Generate strip"]
        XCTAssertTrue(generate.waitForExistence(timeout: timeout))
        XCTAssertTrue(waitUntilEnabled(generate), "Generate stayed disabled; were 4 photos picked?")
        generate.tap()

        let stockPicker = app.buttons["strip.filmStock"]
        XCTAssertTrue(stockPicker.waitForExistence(timeout: timeout), "Strip screen did not open")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: timeout))

        // F12: a new strip starts As shot
        XCTAssertTrue(shows(asShot, picker: stockPicker), "Default stock should be As shot, got \(stockPicker.label) / \(String(describing: stockPicker.value))")
        assertControls(for: asShot, app: app)

        // F8: exactly two swatches, white selected by default
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

        // The menu offers As shot plus the seven stocks. Scroll the card up
        // first: opened at the bottom edge, the eight-row menu clips its
        // last row.
        app.swipeUp()
        stockPicker.tap()
        saveScreenshot(named: "strip-screen-stock-menu")
        for choice in stockChoices {
            XCTAssertTrue(app.buttons[choice].firstMatch.waitForExistence(timeout: timeout), "Menu item \(choice) missing")
        }
        app.buttons[asShot].firstMatch.tap()

        for choice in stocks + [asShot] {
            select(choice, in: stockPicker, app: app)
            assertControls(for: choice, app: app)
        }

        select("Cine 500T", in: stockPicker, app: app)
        saveScreenshot(named: "strip-screen-cine500T")
        select("Mono 400", in: stockPicker, app: app)
        app.swipeUp()
        saveScreenshot(named: "strip-screen-mono400-controls")

        // v4 F15: archive a black-paper strip and check the Library and the
        // detail viewer show it at its own (taller, 4:5-frame) aspect.
        // Adds one strip to the simulator's library.
        select(asShot, in: stockPicker, app: app)
        black.tap()
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: timeout), "Archive should close the strip screen")
        app.tabBars.buttons["Library"].tap()
        app.buttons["Strips"].tap()
        let archived = app.buttons.matching(identifier: "library.strip").firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: timeout), "Archived strip missing from Library")
        saveScreenshot(named: "library-strips-booth")
        archived.tap()
        saveScreenshot(named: "strip-detail-booth")
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
            select(stock, in: stockPicker, app: app)
            XCTAssertTrue(shows(stock, picker: stockPicker), "\(stock): picker should show the choice")
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

    // MARK: Steps

    private func dismissInAppOverlays(_ app: XCUIApplication) {
        // Nudge the interruption monitor, then clear the simulator's
        // "no camera" alert and the first-run walkthrough
        app.tap()
        for label in ["OK", "Skip"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 2) { button.tap() }
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

    // As shot shows no print picker. Gallery picks take the camera's stock
    // (default Off, OPEN v4-10/v4-12), so under As shot every frame is Off
    // and effects are hidden too (F12: hidden only when every effective
    // stock is Off).
    private func assertControls(for stock: String, app: XCUIApplication) {
        let print = app.buttons["strip.print"]
        let halation = app.sliders["strip.slider.halation"]
        let blackAndWhite = app.switches["strip.blackAndWhite"]
        XCTAssertTrue(blackAndWhite.waitForExistence(timeout: timeout), "\(stock): B&W toggle missing")
        // Let the row fade settle before checking absence
        _ = print.waitForNonExistence(timeout: 1)

        let effectsExpected = stock != "Off" && stock != asShot
        XCTAssertEqual(print.exists, !stocksWithoutPrint.contains(stock) && stock != asShot, "\(stock): print picker visibility")
        XCTAssertEqual(halation.exists, effectsExpected, "\(stock): effects visibility")
        if effectsExpected {
            for effect in ["haze", "lightLeak", "grain", "vignette"] {
                XCTAssertTrue(app.sliders["strip.slider.\(effect)"].exists, "\(stock): \(effect) slider missing")
            }
        }
        XCTAssertEqual(blackAndWhite.isEnabled, !monoStocks.contains(stock), "\(stock): B&W lock")
        XCTAssertTrue(app.buttons["Save"].exists, "\(stock): Save missing")
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func saveScreenshot(named name: String) {
        // Give the re-render a moment so the strip reflects the stock
        sleep(2)
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
