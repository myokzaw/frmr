import XCTest

// BUG-521-03: before writing, the text box is short under the full-size
// photo, and a tap on the empty paper below it did nothing, so the keyboard
// never came up. A tap there must give the text view keyboard focus.
// BUG-521-04: on a device, the keyboard's inset re-laid out the live camera
// under the prompt and hung the app (watchdog kill). The real-camera test
// needs a camera, so it runs only on a physical iPhone and skips on the
// simulator.
// Checks focus rather than `app.keyboards`, which stays empty while the
// simulator uses the Mac's hardware keyboard.
final class PromptKeyboardRegressionUITests: XCTestCase {
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testTappingBelowTheTextBoxStartsWriting() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestFast", "-UITestPhotoEdit"]
        app.launch()
        let diary = app.buttons["edit.continueDiary"]
        XCTAssertTrue(diary.waitForExistence(timeout: timeout), "Editor did not open")
        diary.tap()
        let editor = app.textViews["entry.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))

        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: editor.frame.midX, dy: editor.frame.maxY + 80))
            .tap()

        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        expectation(for: focused, evaluatedWith: editor)
        waitForExpectations(timeout: timeout)
    }

    @MainActor
    func testRealCaptureThenTypingDoesNotHang() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestFast"]
        addUIInterruptionMonitor(withDescription: "Camera access") { alert in
            for label in ["Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launch()
        let shutter = app.buttons["camera.shutter"]
        guard shutter.waitForExistence(timeout: timeout), shutter.isEnabled else {
            throw XCTSkip("No usable camera here (simulator, or access denied)")
        }
        app.tap() // lets the interruption monitor answer a pending prompt
        shutter.tap()
        let diary = app.buttons["edit.continueDiary"]
        guard diary.waitForExistence(timeout: 20) else {
            throw XCTSkip("The capture didn't open the editor (Edit after each shot off, or no frames)")
        }
        diary.tap()
        let editor = app.textViews["entry.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: timeout))
        editor.tap()
        editor.typeText("still alive")
        XCTAssertEqual(app.state, .runningForeground, "The app hung or quit when the keyboard opened")
        XCTAssertTrue(app.buttons["entry.save"].isHittable, "The prompt stopped responding")
    }
}
