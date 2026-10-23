import XCTest

// v5.1 F4/F5 UI: capture → editor → Continue to diary → prompt screen →
// entry in the Library. The simulator has no camera, so the editor is opened
// by the DEBUG-only `-UITestPhotoEdit` launch argument (a generated photo);
// Continue to diary really saves the photo to the Roll and the entry really
// links to it. Each run adds one Roll photo and one entry to the simulator.
// Every launch also passes `-UITestFast`. Optional:
// TEST_RUNNER_SHOTS_DIR=<abs dir> (and SHOTS_SUFFIX=dark) write screenshots.
final class DiaryFlowUITests: XCTestCase {
    private let timeout: TimeInterval = 10
    private let editArgument = "-UITestPhotoEdit"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // Continue to diary → prompt (same cover) → Save entry → entry in Entries
    @MainActor
    func testContinueToDiaryWritesAnEntryLinkedToTheRollPhoto() throws {
        let app = launch()
        let diary = app.buttons["edit.continueDiary"]
        XCTAssertTrue(diary.waitForExistence(timeout: timeout), "Editor did not open")
        saveScreenshot(named: "edit-continue-to-diary")
        diary.tap()

        let saveEntry = app.buttons["entry.save"]
        XCTAssertTrue(saveEntry.waitForExistence(timeout: timeout), "Continue to diary should open the prompt screen")
        XCTAssertFalse(app.buttons["edit.save"].exists, "The editor is gone behind the prompt")
        XCTAssertTrue(app.buttons["entry.skip"].exists)
        // v5.2 S4: Skip is a quiet text button at the top; Save entry rides the bottom
        XCTAssertLessThan(app.buttons["entry.skip"].frame.maxY, saveEntry.frame.minY, "Skip at the top, Save entry below")
        XCTAssertGreaterThanOrEqual(saveEntry.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["entry.skip"].frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any)["entry.prompt"].exists, "The prompt is one readable element")
        let text = "UITest reflection \(Int(Date().timeIntervalSince1970))"
        let editor = app.textViews["entry.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.tap()
        editor.typeText(text)
        saveScreenshot(named: "diary-prompt")
        saveEntry.tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Saving the entry returns to the camera")
        XCTAssertFalse(saveEntry.exists)
        XCTAssertTrue(app.buttons["camera.lastPhoto"].waitForExistence(timeout: timeout), "The photo is in the Roll (Roll plus diary)")

        // The entry is in Library → Entries
        app.tabBars.buttons["Library"].tap()
        let entries = app.segmentedControls.buttons["Entries"]
        XCTAssertTrue(entries.waitForExistence(timeout: timeout))
        entries.tap()
        let entry = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: timeout), "The entry is missing from the diary list")
        saveScreenshot(named: "diary-entries-list", settle: 2)
    }

    // Skip saves the entry without text and ends the flow; deleting the Roll
    // photo then asks what to do with its entry (v5.1-7)
    @MainActor
    func testSkipThenDeleteThePhotoAsksAboutTheEntry() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["edit.continueDiary"].waitForExistence(timeout: timeout))
        app.buttons["edit.continueDiary"].tap()
        let skip = app.buttons["entry.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: timeout), "Prompt screen missing")
        skip.tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Skip returns to the camera")

        // Re-edit the newest Roll photo (the one just saved) and delete it
        let last = app.buttons["camera.lastPhoto"]
        XCTAssertTrue(last.waitForExistence(timeout: timeout))
        last.tap()
        XCTAssertTrue(app.buttons["edit.delete"].waitForExistence(timeout: timeout), "Re-edit offers Delete")
        XCTAssertFalse(app.buttons["edit.continueDiary"].exists, "No Continue to diary in re-edit")
        app.buttons["edit.delete"].tap()
        let keep = app.buttons["edit.delete.keepEntry"]
        XCTAssertTrue(keep.waitForExistence(timeout: timeout), "A photo with an entry asks what to do with the entry")
        XCTAssertTrue(app.buttons["edit.delete.confirmBoth"].exists, "Delete photo and diary entry is offered")
        XCTAssertFalse(app.buttons["edit.delete.confirm"].exists)
        saveScreenshot(named: "edit-delete-with-entry")
        keep.firstMatch.tap()
        XCTAssertTrue(app.buttons["camera.mode.photo"].waitForExistence(timeout: timeout), "Delete returns to the camera")
        XCTAssertFalse(app.buttons["edit.delete"].exists)
    }

    // MARK: Steps

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let dark = ProcessInfo.processInfo.environment["SHOTS_SUFFIX"] == "dark"
        app.launchArguments = ["-UITestFast", editArgument] + (dark ? ["-AppleInterfaceStyle", "Dark"] : [])
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow", "OK", "Allow Full Access"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        app.tap()
        // The first-run walkthrough has its own Skip; the prompt's is "entry.skip"
        for _ in 0..<2 {
            for label in ["OK", "Skip"] {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 3) { button.tap() }
            }
        }
        return app
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
