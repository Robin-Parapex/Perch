import XCTest

final class DesignGalleryUITests: XCTestCase {
    @MainActor
    func testOverlaysReturnFocusToTheirButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchDesignGallery"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.descendants(matching: .any)["designGallery"].waitForExistence(timeout: 10))
        let sidePanelButton = app.buttons["gallery.showSidePanel"]
        XCTAssertTrue(sidePanelButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(sidePanelButton), "sidePanelButton should have focus")

        remote.press(.select)
        let close = app.buttons["sidePanel.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(close), "close should have focus")
        remote.press(.menu)
        XCTAssertTrue(waitForGone(close))
        XCTAssertTrue(waitForFocus(sidePanelButton), "sidePanelButton should have focus")

        remote.press(.right)
        let topSheetButton = app.buttons["gallery.showTopSheet"]
        XCTAssertTrue(waitForFocus(topSheetButton), "topSheetButton should have focus")
        remote.press(.select)
        let sheetClose = app.buttons["topSheet.close"]
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(sheetClose), "sheetClose should have focus")
        remote.press(.menu)
        XCTAssertTrue(waitForGone(sheetClose))
        XCTAssertTrue(waitForFocus(topSheetButton), "topSheetButton should have focus")

        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Perch"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCornerPillTakesAndReturnsFocus() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchDesignGallery"]
        app.launch()
        let remote = XCUIRemote.shared

        let sidePanelButton = app.buttons["gallery.showSidePanel"]
        XCTAssertTrue(sidePanelButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(sidePanelButton), "sidePanelButton should have focus")
        let pillButton = app.buttons["gallery.showCornerPill"]
        for _ in 0..<3 { remote.press(.right) }
        XCTAssertTrue(waitForFocus(pillButton), "pillButton should have focus")

        remote.press(.select)
        let pill = app.buttons["Skip intro"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(pill), "pill should have focus")
        remote.press(.menu)
        XCTAssertTrue(waitForGone(pill))
        XCTAssertTrue(waitForFocus(pillButton), "pillButton should have focus")

        remote.press(.menu)
        XCTAssertTrue(app.staticTexts["Perch"].waitForExistence(timeout: 5))
    }

    private func waitForFocus(_ element: XCUIElement) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        return XCTWaiter().wait(for: [focused], timeout: 3) == .completed
    }

    private func waitForGone(_ element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
    }
}
