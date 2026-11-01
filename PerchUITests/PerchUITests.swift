import XCTest

final class PerchUITests: XCTestCase {
    @MainActor
    func testLaunchShowsPerchWordmark() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Perch"].waitForExistence(timeout: 10))
    }
}
