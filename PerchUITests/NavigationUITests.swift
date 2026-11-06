import XCTest

/// WP-13: the sidebar and navigation rules on the DEBUG fake household (noPINs, Robin 1001, Sam 1003 is a kid).
/// Back pops inside a tab, Back at a tab's root moves focus to the sidebar, Back in the sidebar shows a hint and a
/// second Back within 2 s leaves the app, double-tap Back returns to Home's root, focus comes back to the last item
/// after a tab switch, Right and Select enter a tab's content, the avatar opens the picker.
final class NavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Wizard, profile, Home with focus on the hero.
    @MainActor
    private func reachHome(_ profile: Int = 1001) throws -> XCUIApplication {
        let app = launchApp(.noPINs, extraArguments: ["-PerchUITests"])
        try completeWizard(app, .noPINs)
        if element(app, "root.picker").exists { pickProfile(profile, app) }
        waitFor(element(app, "home.root"), timeout: 20)
        enterContentIfSidebarFocused(app)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.hero.action").hasFocus }, "focus on the hero")
        return app
    }

    // MARK: Helpers

    @MainActor
    private func focused(_ app: XCUIApplication) -> XCUIElement? {
        let all = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        return all.last { $0.elementType != .window && $0.elementType != .other } ?? all.last
    }

    @MainActor
    private func describeFocus(_ app: XCUIApplication) -> String {
        guard let now = focused(app) else { return "nothing" }
        return "\(now.elementType.rawValue) id=\(now.identifier) label=\(now.label) frame=\(now.frame)"
    }

    private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement { sidebarTab(app, label) }

    private func focusInSidebar(_ app: XCUIApplication) -> Bool { sidebarHasFocus(app) }

    @MainActor
    private func press(_ button: XCUIRemote.Button, settle: TimeInterval = 0.6) {
        XCUIRemote.shared.press(button)
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
    }

    /// Two Menu presses well inside the 0.4 s window.
    @MainActor
    private func doubleBack() {
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    // MARK: Tests

    @MainActor
    func testBackInSidebarNeedsADoublePressToLeave() throws {
        let app = try reachHome()
        shot("wp13-home-collapsed")
        press(.menu)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "Back at the hero moves focus to the sidebar; focus: \(describeFocus(app))")
        shot("wp13-sidebar-expanded")
        // One Back in the sidebar: the hint, and the app stays.
        press(.menu, settle: 0.5)
        XCTAssertEqual(app.state, .runningForeground, "one Back in the sidebar does not leave the app")
        XCTAssertTrue(element(app, "shell.leaveHint").exists, "the hint asks for a second press")
        // At once (no settle): the hint lasts only the 2 s window.
        let hint = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        hint.name = "wp13-leave-hint"
        hint.lifetime = .keepAlways
        add(hint)
        XCTAssertTrue(focusInSidebar(app), "focus stays in the sidebar; focus: \(describeFocus(app))")
        XCTAssertFalse(element(app, "picker.title").exists, "Back in the sidebar never opens the picker")
        // The window closes by itself.
        XCTAssertTrue(waitForGone(element(app, "shell.leaveHint"), timeout: 5), "the hint fades after the window")
        press(.menu, settle: 0.5)
        XCTAssertEqual(app.state, .runningForeground, "a Back after the window has closed starts again")
        // Two quick presses leave.
        press(.menu, settle: 0.2)
        XCTAssertTrue(waitUntil(5) { app.state == .runningBackground || app.state == .runningBackgroundSuspended }, "two Backs in the sidebar leave the app; state \(app.state.rawValue)")
    }

    @MainActor
    func testTabSwitchReturnsFocusToLastItem() throws {
        let app = try reachHome()
        press(.down)
        press(.right)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.1001").hasFocus }, "on card 1001; focus: \(describeFocus(app))")
        press(.menu)  // card -> hero
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.hero.action").hasFocus }, "Back on a card goes to the hero")
        press(.down)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.1001").hasFocus }, "Down returns to the remembered card")
        // Card -> hero -> sidebar, spaced so the two are not a double tap.
        press(.menu)
        press(.menu)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "in the sidebar; focus: \(describeFocus(app))")
        // To Films and back to Home.
        XCTAssertTrue(focus(tab(app, "Films"), in: app), "Films in the sidebar")
        press(.select)
        XCTAssertTrue(waitUntil(5) { self.element(app, "films.empty").exists }, "the Films placeholder shows")
        XCTAssertTrue(waitUntil(5) { self.element(app, "films.empty").hasFocus }, "the empty Films page holds focus; focus: \(describeFocus(app))")
        XCTAssertFalse(focusInSidebar(app))
        shot("wp13-films-placeholder")
        press(.menu)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "Back from Films goes to the sidebar; focus: \(describeFocus(app))")
        XCTAssertTrue(focus(tab(app, "Home"), in: app), "Home in the sidebar")
        press(.select, settle: 1)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.root").isHittable }, "Home shows again")
        enterContentIfSidebarFocused(app)
        // Back at the hero went through the hero, so the hero is the last focus; the card is remembered per row.
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.hero.action").hasFocus }, "focus returns to the last item; focus: \(describeFocus(app))")
        press(.down)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.1001").hasFocus }, "the row still remembers its card")
    }

    @MainActor
    func testFocusReturnsToCardAfterVisitingSidebar() throws {
        let app = try reachHome()
        press(.down)
        press(.right)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.1001").hasFocus }, "on card 1001")
        // Left along the row to its first card, then Left again into the sidebar.
        press(.left)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.2101").hasFocus }, "on card 2101; focus: \(describeFocus(app))")
        press(.left)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "Left from the first card reaches the sidebar; focus: \(describeFocus(app))")
        press(.right, settle: 1)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.card.2101").hasFocus }, "Right lands on the last focused card; focus: \(describeFocus(app))")
    }

    @MainActor
    func testRightFromSettingsCellEntersSettings() throws {
        let app = try reachHome()
        openSettings(app)
        XCTAssertTrue(waitUntil(5) { self.element(app, "settings.switchProfile").hasFocus }, "Select on Settings enters it; focus: \(describeFocus(app))")
        press(.menu)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "Back at Settings' root goes to the sidebar; focus: \(describeFocus(app))")
        press(.right, settle: 1)
        XCTAssertTrue(waitUntil(5) { self.element(app, "settings.switchProfile").hasFocus }, "Right from the Settings cell enters Settings; focus: \(describeFocus(app))")
        press(.down)
        XCTAssertTrue(waitUntil(5) { self.element(app, "settings.runSetup").hasFocus || self.element(app, "settings.gallery").hasFocus }, "Down reaches the setup buttons; focus: \(describeFocus(app))")
    }

    @MainActor
    func testDoubleBackReturnsToHomeRoot() throws {
        let app = try reachHome()
        openSettings(app)
        tap("settings.gallery", in: app)
        XCTAssertTrue(element(app, "designGallery").waitForExistence(timeout: 5), "the gallery is pushed on the Settings stack")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        doubleBack()
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.root").isHittable }, "double-tap Back shows Home")
        XCTAssertFalse(element(app, "designGallery").exists, "the pushed screen is gone")
        XCTAssertEqual(app.state, .runningForeground, "double-tap Back from a pushed screen does not leave the app")
        XCTAssertFalse(element(app, "shell.leaveHint").exists, "double-tap Back disarms the leave: no hint on Home")
        // The second press reached Settings' root and moved focus to the sidebar before the double tap was known;
        // the sidebar keeps it (it ignores focus requests), so focus is on Home's item, one Right from the hero.
        let home = tab(app, "Home")
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.hero.action").hasFocus || home.hasFocus }, "focus on the hero or Home's sidebar item; focus: \(describeFocus(app))")
        enterContentIfSidebarFocused(app)
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.hero.action").hasFocus }, "Right reaches the hero; focus: \(describeFocus(app))")
    }

    @MainActor
    func testBackPopsWithinTab() throws {
        let app = try reachHome()
        openSettings(app)
        tap("settings.gallery", in: app)
        XCTAssertTrue(element(app, "designGallery").waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(5) { self.focused(app).map { $0.elementType != .window } ?? false }, "the pushed screen takes focus; focus: \(describeFocus(app))")
        press(.menu, settle: 1)
        XCTAssertTrue(waitUntil(5) { self.element(app, "settings.root").exists && !self.element(app, "designGallery").exists }, "Back pops to Settings")
        XCTAssertTrue(waitUntil(5) { self.element(app, "settings.gallery").hasFocus }, "focus returns to the button; focus: \(describeFocus(app))")
    }

    @MainActor
    func testAvatarOpensPicker() throws {
        let app = try reachHome()
        press(.menu)
        XCTAssertTrue(waitUntil(5) { self.focusInSidebar(app) }, "in the sidebar")
        tap("sidebar.profile", in: app)
        XCTAssertTrue(element(app, "picker.title").waitForExistence(timeout: 5), "the avatar opens the picker")
        XCTAssertTrue(waitUntil(5) { self.element(app, "profile.1001").hasFocus }, "the picker takes focus")
        press(.menu, settle: 1)
        XCTAssertTrue(waitForGone(element(app, "picker.title")), "Back closes the picker")
        XCTAssertTrue(waitUntil(5) { self.element(app, "sidebar.profile").hasFocus }, "focus returns to the avatar; focus: \(describeFocus(app))")
    }

    @MainActor
    func testKidSidebar() throws {
        let app = try reachHome()
        press(.menu)
        tap("sidebar.profile", in: app)
        XCTAssertTrue(element(app, "picker.title").waitForExistence(timeout: 5))
        tap("profile.1003", in: app)  // Sam, kid
        XCTAssertTrue(waitUntil(15) { self.text(self.element(app, "home.profileName")) == "Sam" }, "home as Sam")
        XCTAssertTrue(waitUntil(5) { self.element(app, "home.root").isHittable })
        // Focus returns to the avatar that opened the picker, now Sam's.
        XCTAssertTrue(waitUntil(8) { self.element(app, "sidebar.profile").hasFocus }, "the avatar has focus; focus: \(describeFocus(app))")
        XCTAssertEqual(text(element(app, "sidebar.profile")), "Sam")
        XCTAssertTrue(focusInSidebar(app))
        shot("wp13-kid-sidebar")
    }
}
