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

    @MainActor
    func testSignInFillsTheScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchPlexSignIn"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let title = app.staticTexts["plexSignIn.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.frame.minX - window.frame.minX, 80, accuracy: 4, "title sits at the 80 pt margin")
    }

    @MainActor
    func testConnectedProfilesOpensProfiles() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchPlexConnected"]
        app.launch()
        let remote = XCUIRemote.shared

        let profiles = app.buttons["plexConnected.profiles"]
        XCTAssertTrue(profiles.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(profiles), "Profiles should start focused")
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["plexProfiles.title"].waitForExistence(timeout: 5), "Profiles should open")

        remote.press(.menu)
        XCTAssertTrue(app.buttons["plexConnected.profiles"].waitForExistence(timeout: 5), "Back returns to Connected")
    }

    @MainActor
    func testFourthDigitSubmitsThePIN() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchPlexConnected"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.buttons["plexConnected.profiles"].waitForExistence(timeout: 10))
        remote.press(.select)
        let check = app.buttons["plexProfiles.checkAdmin"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        for _ in 0..<6 where !check.hasFocus { remote.press(.down) }
        XCTAssertTrue(waitForFocus(check), "Check Admin PIN should be reachable")
        remote.press(.select)

        XCTAssertTrue(app.buttons["pinPad.1"].waitForExistence(timeout: 5))
        for _ in 0..<4 { remote.press(.select) }
        // What matters is that the check ran without another press. Not signed in, so a signed build
        // cannot reach Plex; an unsigned test build has no Keychain entitlement, so it cannot read
        // the stored Admin PIN either. Either refusal proves the fourth digit submitted.
        let message = app.staticTexts["plexProfiles.pinMessage"]
        let shown = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label IN %@", ["The PIN can't be checked right now", "Couldn't read the Admin PIN"]),
            object: message)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 5), .completed, "the fourth digit submits")
    }

    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: 3) == .completed
    }
}
