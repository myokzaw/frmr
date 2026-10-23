import XCTest

// BUG-521-03: before writing, the text box is short under the full-size
// photo, and a tap on the empty paper below it did nothing, so the keyboard
// never came up. A tap there must give the text view keyboard focus.
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
}
