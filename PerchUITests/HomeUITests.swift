import XCTest

/// WP-09: the Home screen on the DEBUG fake household (noPINs). Fake library: Continue watching = episode 2101,
/// film 1001; Up next = episode 3102; Recently added = 3 items. `-PerchUITests` stops the hero's Ken Burns pan.
final class HomeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Wizard, profile, Home.
    @MainActor
    private func reachHome(_ extra: [String] = []) throws -> XCUIApplication {
        let app = launchApp(.noPINs, extraArguments: ["-PerchUITests"] + extra)
        try completeWizard(app, .noPINs)
        if element(app, "root.picker").exists { pickProfile(1001, app) }
        waitFor(element(app, "home.root"), timeout: 20)
        RunLoop.current.run(until: Date().addingTimeInterval(2))  // let the first render settle
        return app
    }

    private func hasFocus(_ app: XCUIApplication, _ id: String) -> Bool {
        let el = element(app, id)
        let ok = waitUntil(5) { el.hasFocus }
        return ok
    }

    /// Leaves the player cover: Menu, wait up to 4 s for Home to be hittable, at most 4 presses (the player may
    /// first close its own transport bar or finish loading).
    @MainActor
    private func backToHome(_ app: XCUIApplication) {
        for _ in 0..<4 {
            back()
            if waitUntil(4, { self.element(app, "home.row.plex.continueWatching").isHittable }) { break }
        }
        XCTAssertTrue(element(app, "home.row.plex.continueWatching").isHittable, "Home visible again after Back")
    }

    @MainActor
    func testLaunchFocusIsHeroAction() throws {
        let app = try reachHome()
        XCTAssertTrue(hasFocus(app, "home.hero.action"), "focus starts on the hero action")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner on Home")
        shot("home-launch")
    }

    @MainActor
    func testResumeInTwoClicks() throws {
        let app = try reachHome()
        XCTAssertTrue(hasFocus(app, "home.hero.action"))
        var presses = 0
        XCUIRemote.shared.press(.select); presses += 1
        XCTAssertTrue(waitUntil(10) { !self.element(app, "home.root").isHittable }, "player cover opens after one Select")
        XCTAssertLessThanOrEqual(presses, 1, "resume is one click")
        backToHome(app)

        // First Continue watching card: Down, Select.
        let first = element(app, "home.card.2101")
        waitFor(first)
        XCUIRemote.shared.press(.down); presses = 1
        XCTAssertTrue(hasFocus(app, "home.card.2101"), "Down lands on the first Continue watching card")
        XCUIRemote.shared.press(.select); presses += 1
        XCTAssertEqual(presses, 2)
        XCTAssertTrue(waitUntil(10) { !self.element(app, "home.root").isHittable }, "player cover opens from the card")
    }

    @MainActor
    func testBackReturnsToCard() throws {
        let app = try reachHome()
        XCTAssertTrue(hasFocus(app, "home.hero.action"))
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(hasFocus(app, "home.card.1001"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil(10) { !self.element(app, "home.root").isHittable }, "player opens")
        backToHome(app)
        XCTAssertTrue(hasFocus(app, "home.card.1001"), "Back returns focus to the card")
        XCTAssertTrue(element(app, "home.row.plex.continueWatching").isHittable)
        shot("home-back")
    }

    @MainActor
    func testRowFocusMemory() throws {
        let app = try reachHome()
        XCTAssertTrue(hasFocus(app, "home.hero.action"))
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(hasFocus(app, "home.card.1001"))
        XCUIRemote.shared.press(.down)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(element(app, "home.card.1001").hasFocus, "Down moves to the next row")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(hasFocus(app, "home.card.1001"), "Up returns to the remembered card")
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(hasFocus(app, "home.hero.action"), "Up again reaches the hero action")
    }

    @MainActor
    func testCachedRenderOnSecondLaunchHasNoSpinner() throws {
        var app = try reachHome()
        waitFor(element(app, "home.row.plex.continueWatching"))
        app = relaunch(app, extraArguments: ["-PerchFakeServerDown"])
        waitFor(element(app, "home.root"), timeout: 20)
        waitFor(element(app, "home.row.plex.continueWatching"), timeout: 10, "snapshot renders")
        XCTAssertTrue(element(app, "home.card.1001").exists || element(app, "home.card.2101").exists, "cards from the snapshot")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner on a cached launch")
        waitFor(element(app, "home.serverDown"), timeout: 5, "offline notice")
        shot("home-offline")
    }

    @MainActor
    func testEmptyLibraryShowsMessage() throws {
        let app = try reachHome(["-PerchFakeEmptyLibrary"])
        waitFor(element(app, "home.message"), timeout: 15)
        XCTAssertTrue(app.staticTexts["Nothing to watch yet"].exists, "empty title shown")
        XCTAssertTrue(element(app, "home.message.secondary").exists)
        for id in ["plex.continueWatching", "plex.upNext", "plex.recentlyAdded"] {
            XCTAssertFalse(element(app, "home.row.\(id)").exists, "no row \(id)")
        }
        shot("home-empty")
    }

    @MainActor
    func testProfileMenuOpensSheet() throws {
        let app = try reachHome()
        XCTAssertTrue(hasFocus(app, "home.hero.action"))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(hasFocus(app, "home.profileMenu"), "Right from the hero lands on the profile menu")
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "home.switchProfile"))
        back()
        XCTAssertTrue(waitForGone(element(app, "home.switchProfile")), "Back closes the sheet")
        XCTAssertTrue(hasFocus(app, "home.profileMenu"), "focus returns to the profile menu")
    }
}
