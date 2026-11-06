import XCTest

final class DesignGalleryUITests: XCTestCase {
    @MainActor
    func testOverlaysReturnFocusToTheirButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchDesignGallery", "-PerchUITests"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.descendants(matching: .any)["designGallery"].waitForExistence(timeout: 10))
        let sidePanelButton = app.buttons["gallery.showSidePanel"]
        XCTAssertTrue(sidePanelButton.waitForExistence(timeout: 5))
        // The gallery sits on Home's stack in the sidebar shell, which takes the first focus (WP-13).
        enterContentIfSidebarFocused(app)
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
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 5), "Back from the gallery returns to Home")
    }

    @MainActor
    func testCornerPillTakesAndReturnsFocus() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchDesignGallery", "-PerchUITests"]
        app.launch()
        let remote = XCUIRemote.shared

        let sidePanelButton = app.buttons["gallery.showSidePanel"]
        XCTAssertTrue(sidePanelButton.waitForExistence(timeout: 10))
        enterContentIfSidebarFocused(app)
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
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 5), "Back from the gallery returns to Home")
    }

    @MainActor
    func testGalleryFillsTheScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchDesignGallery", "-PerchUITests"]
        app.launch()
        let remote = XCUIRemote.shared

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let title = app.staticTexts["gallery.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.frame.minX - window.frame.minX, 80, accuracy: 4, "title sits at the 80 pt margin")

        let hero = app.descendants(matching: .any)["gallery.hero"]
        var presses = 0
        while !hero.exists && presses < 12 {
            remote.press(.down)
            presses += 1
        }
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "hero should be reachable")
        XCTAssertEqual(hero.frame.width, window.frame.width, accuracy: 1, "hero spans the window")
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
