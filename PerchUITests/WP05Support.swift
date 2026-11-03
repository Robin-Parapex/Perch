import XCTest

/// Shared helpers for the WP-05 UI tests (setup wizard and profile picker). Everything runs on the
/// DEBUG fake household (`FakeHouseholdTransport`): link code PRCH, fake Plex PIN 1234, server "Living room".
enum Household: String {
    case withPINs, noPINs
}

/// The Plex PIN the fake accepts for protected users and for the owner.
let fakePlexPIN = "1234"

extension XCTestCase {
    // MARK: Launch

    @MainActor
    func launchApp(
        _ household: Household, reset: Bool = true, plexTVDown: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-PerchFakeHousehold", household.rawValue]
        if reset { arguments.append("-PerchResetSetup") }
        if plexTVDown { arguments.append("-PerchFakePlexTVDown") }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    // MARK: Elements and waiting

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "Expected \(element) to appear. \(message)", file: file, line: line)
        return found
    }

    func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    func waitForGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        waitUntil(timeout) { !element.exists }
    }

    /// The text of an element (label or value).
    func text(_ element: XCUIElement) -> String {
        let label = element.label
        return label.isEmpty ? (element.value as? String ?? "") : label
    }

    // MARK: Focus

    private func focusedElement(_ app: XCUIApplication) -> XCUIElement? {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        return focused.filter { $0.frame.width > 0 && $0.elementType != .window && $0.elementType != .other }.first
            ?? focused.first
    }

    /// Moves focus to `target` with the remote, choosing the direction from the frames. Gives up after 25 presses.
    @MainActor
    @discardableResult
    func focus(_ target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard target.waitForExistence(timeout: 10) else {
            XCTFail("Cannot focus \(target): not on screen", file: file, line: line)
            return false
        }
        let remote = XCUIRemote.shared
        var lastDirection: XCUIRemote.Button?
        var tried = Set<String>()
        for _ in 0..<25 {
            if target.hasFocus { return true }
            if let now = focusedElement(app), now.frame.width > 0,
                abs(now.frame.midX - target.frame.midX) < 4, abs(now.frame.midY - target.frame.midY) < 4 { return true }
            guard let current = focusedElement(app) else {
                // Nothing focused (a new screen with no default focus yet): a press wakes the focus engine.
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                if focusedElement(app) == nil { remote.press(.down) }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                continue
            }
            let dx = target.frame.midX - current.frame.midX
            let dy = target.frame.midY - current.frame.midY
            // Rows first: vertical while the target is on another row, then horizontal along the row.
            var direction: XCUIRemote.Button = abs(dy) > 40 ? (dy > 0 ? .down : .up) : (dx > 0 ? .right : .left)
            // If the same press from the same place did nothing before, try the other axis.
            let key = "\(Int(current.frame.midX)),\(Int(current.frame.midY))-\(direction.rawValue)"
            if tried.contains(key) {
                direction = abs(dy) > 40 ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
            }
            tried.insert(key)
            lastDirection = direction
            remote.press(direction)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        _ = lastDirection
        if target.hasFocus { return true }
        let now = focusedElement(app)
        XCTFail("Could not move focus to \(target) label=\(target.label) frame=\(target.frame) hasFocus=\(target.hasFocus); focused is \(String(describing: now?.identifier)) \(String(describing: now?.frame))", file: file, line: line)
        return false
    }

    /// Focus the element and press select.
    @MainActor
    func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(app, id)
        if focus(target, in: app, file: file, line: line) {
            XCUIRemote.shared.press(.select)
        }
    }

    /// Select a button by its title or id.
    @MainActor
    func tapButton(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let target = app.buttons[title].firstMatch
        if focus(target, in: app, file: file, line: line) {
            XCUIRemote.shared.press(.select)
        }
    }

    @MainActor
    func back() {
        XCUIRemote.shared.press(.menu)
    }

    // MARK: PIN pad

    /// Types digits on the PIN pad with the remote.
    @MainActor
    func enterPIN(_ digits: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for digit in digits {
            let key = element(app, "pinPad.\(digit)")
            if focus(key, in: app, file: file, line: line) { XCUIRemote.shared.press(.select) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    /// Waits for a PIN screen error with exactly this text (or starting with it) and returns it.
    @MainActor
    @discardableResult
    func expectPINError(_ expected: String, in app: XCUIApplication, prefixOnly: Bool = false, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = waitUntil(timeout) {
            let error = self.element(app, "pinEntry.error")
            guard error.exists else { return false }
            let shown = self.text(error)
            return prefixOnly ? shown.hasPrefix(expected) : shown == expected
        }
        XCTAssertTrue(ok, "PIN error '\(expected)' not shown", file: file, line: line)
        return ok
    }

    // MARK: Screenshots

    func shot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))  // let transitions settle
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Wizard walk

    /// Welcome through to the Admin PIN intro, with the Plex steps and screenshots (prefix names them).
    @MainActor
    func walkToAdminPIN(_ app: XCUIApplication, shots: Bool = true, prefix: String = "") throws {
        waitFor(element(app, "root.setup"))
        waitFor(app.staticTexts["Welcome to Perch"])
        if shots { shot("\(prefix)01-welcome") }
        tap("setup.primary", in: app)  // Get started

        waitFor(app.staticTexts["Connect Plex"])
        if shots { shot("\(prefix)02-connect-choice") }
        tap("setup.primary", in: app)  // Sign in with a code

        let code = element(app, "setup.code.value")
        waitFor(code)
        XCTAssertTrue(waitUntil(10) { self.text(code) == "PRCH" }, "link code PRCH shown, got '\(text(code))'")
        if shots { shot("\(prefix)03-link-code") }

        // The fake links on the second poll: the screen moves on by itself.
        let summary = element(app, "setup.connected.summary")
        let saveError = app.staticTexts["Couldn't save your sign-in"]
        _ = waitUntil(30) { summary.exists || saveError.exists }
        if saveError.exists {
            // An unsigned build (CODE_SIGNING_ALLOWED=NO, as scripts/gate.sh builds) has no Keychain access group,
            // so no sign-in can be stored. These tests need a signed simulator build; skip rather than fail.
            throw XCTSkip("Keychain unavailable (unsigned build): the fake household sign-in cannot be saved")
        }
        waitFor(summary, timeout: 5, "wizard should move on after linking")
        XCTAssertTrue(waitUntil(10) { self.text(summary) == "Connected to Living room, 2 libraries" }, "summary was '\(text(summary))'")
        if shots { shot("\(prefix)04-connected") }
        tap("setup.primary", in: app)  // Continue

        waitFor(element(app, "setup.admin.status"))
    }

    /// Waits for "Plex is connected"; skips on an unsigned build where the sign-in cannot be stored.
    @MainActor
    func waitConnected(_ app: XCUIApplication) throws {
        let summary = element(app, "setup.connected.summary")
        let saveError = app.staticTexts["Couldn't save your sign-in"]
        _ = waitUntil(30) { summary.exists || saveError.exists }
        if saveError.exists { throw XCTSkip("Keychain unavailable (unsigned build): the sign-in cannot be saved") }
        waitFor(summary, timeout: 5)
    }

    /// After the wizard: waits for home or the picker; from home opens "Switch profile".
    @MainActor
    func reachPicker(_ app: XCUIApplication) {
        XCTAssertTrue(waitUntil(20) { self.element(app, "root.home").exists || self.element(app, "root.picker").exists })
        if element(app, "home.switchProfile").exists { tap("home.switchProfile", in: app) }
        waitFor(element(app, "picker.title"))
    }

    /// The whole wizard without screenshots. Admin PIN: the fake Plex PIN, or a Perch PIN "1111" when none.
    @MainActor
    func completeWizard(_ app: XCUIApplication, _ household: Household) throws {
        try walkToAdminPIN(app, shots: false)
        tap("setup.primary", in: app)
        waitFor(element(app, "pinPad.1"))
        if household == .withPINs {
            enterPIN(fakePlexPIN, in: app)
        } else {
            enterPIN(adminPerchPIN, in: app)
            waitFor(app.staticTexts["Enter it again to confirm"])
            enterPIN(adminPerchPIN, in: app)
        }
        waitFor(app.staticTexts["Profiles and roles"], timeout: 15)
        tap("setup.primary", in: app)
        waitFor(app.staticTexts["More to add later"])
        tap("setup.primary", in: app)
        waitFor(app.staticTexts["You're all set"])
        tap("setup.primary", in: app)
        XCTAssertTrue(waitUntil(20) { self.element(app, "root.home").exists || self.element(app, "root.picker").exists })
    }

    /// Picks a profile on the picker.
    @MainActor
    func pickProfile(_ id: Int, _ app: XCUIApplication) {
        tap("profile.\(id)", in: app)
    }

    /// Relaunches the app without wiping state.
    @MainActor
    func relaunch(_ app: XCUIApplication, plexTVDown: Bool = false) -> XCUIApplication {
        app.terminate()
        var arguments = app.launchArguments.filter { $0 != "-PerchResetSetup" && $0 != "-PerchFakePlexTVDown" }
        if plexTVDown { arguments.append("-PerchFakePlexTVDown") }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

/// The Perch Admin PIN the tests choose when the fake Plex owner has no PIN.
let adminPerchPIN = "1111"
