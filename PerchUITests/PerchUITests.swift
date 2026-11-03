import XCTest

final class PerchUITests: XCTestCase {
    /// First launch on a clean install opens the setup wizard, whatever the simulator held before.
    @MainActor
    func testFirstLaunchShowsWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchResetSetup", "-PerchFakeHousehold", "withPINs"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to Perch"].waitForExistence(timeout: 10))
    }
}
