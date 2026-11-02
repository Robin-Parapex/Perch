import XCTest

final class PlexSignInUITests: XCTestCase {
    @MainActor
    func testChoicesAddressScreenAndBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchPlexSignIn"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.staticTexts["plexSignIn.title"].waitForExistence(timeout: 10))
        let code = app.buttons["plexSignIn.code"]
        let address = app.buttons["plexSignIn.address"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(address.exists)
        XCTAssertTrue(waitForFocus(code), "code choice should start focused")

        remote.press(.down)
        XCTAssertTrue(waitForFocus(address), "down should move to the address choice")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["plexAddress.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["plexAddress.field"].waitForExistence(timeout: 5))

        remote.press(.menu)
        XCTAssertTrue(app.buttons["plexSignIn.code"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["plexSignIn.address"].exists)

        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Perch"].waitForExistence(timeout: 5))
    }

    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: 3) == .completed
    }
}
