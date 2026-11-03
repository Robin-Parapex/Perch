import XCTest

/// WP-05 acceptance, wizard side: runs the first-run wizard on the DEBUG fake household.
/// Every distinct screen is attached as a screenshot (keepAlways) for the walk-through.
final class SetupWizardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Plex only, with a Plex PIN on the owner: the whole wizard, Welcome to the picker.
    @MainActor
    func testWithPINsWizardCompletesAndLandsOnPicker() throws {
        let app = launchApp(.withPINs)
        try walkToAdminPIN(app)

        // Admin PIN intro: the Plex PIN route.
        let plexRoute = app.buttons["Use your Plex PIN"]
        XCTAssertTrue(plexRoute.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Set a Perch PIN instead"].exists, "the Perch PIN route is the secondary button")
        XCTAssertTrue(waitUntil(5) { plexRoute.hasFocus }, "focus starts on the primary route")
        shot("05-admin-pin-intro")
        tap("setup.primary", in: app)

        waitFor(element(app, "pinPad.1"))
        XCTAssertTrue(app.staticTexts["Enter your Plex PIN"].exists)
        shot("06-admin-pin-entry")
        enterPIN(fakePlexPIN, in: app)

        // Accepted: moves on to Profiles by itself.
        waitFor(app.staticTexts["Profiles and roles"], timeout: 15)
        // One role pill per household member, found by its per-row identifier.
        let rolePills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'setup.profile.' AND identifier ENDSWITH '.role'"))
        XCTAssertTrue(waitUntil(10) { rolePills.count == 3 }, "three role pills, got \(rolePills.count)")
        shot("07-profiles")
        tap("setup.primary", in: app)

        // Add later: every entry says "Coming soon".
        waitFor(app.staticTexts["More to add later"])
        let ids = ["seerr", "library-refresh", "trakt", "homeassistant", "tautulli", "ai"]
        for id in ids {
            let row = element(app, "setup.addLater.\(id)")
            XCTAssertTrue(row.exists, "add-later entry \(id)")
            XCTAssertTrue(row.label.contains("Coming soon"), "\(id) says Coming soon, got '\(row.label)'")
        }
        XCTAssertFalse(element(app, "setup.skip").exists, "add later has Continue only")
        shot("08-add-later")
        tap("setup.primary", in: app)

        waitFor(app.staticTexts["You're all set"])
        shot("09-done")
        tap("setup.primary", in: app)

        // Setup is complete: "Choose who's watching" lands on the picker, which shows the whole household.
        waitFor(element(app, "root.picker"), timeout: 20)
        waitFor(element(app, "picker.title"))
        for id in ["profile.1001", "profile.1002", "profile.1003"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "\(id) on the picker")
        }
        shot("10-picker")
    }

    /// Without a Plex PIN the owner must choose a Perch PIN, entered twice; a mismatch is refused.
    @MainActor
    func testNoPINsWizardRequiresPerchPINAndRefusesMismatch() throws {
        let app = launchApp(.noPINs)
        try walkToAdminPIN(app)

        XCTAssertTrue(app.buttons["Set a Perch PIN"].waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "setup.skip").exists, "the Admin PIN step cannot be skipped")
        shot("11-admin-pin-intro-no-plex-pin")

        // The wizard cannot get past the step without a PIN: Continue is not offered, Back leaves, never forward.
        XCTAssertFalse(app.buttons["Continue"].exists)
        XCTAssertFalse(app.staticTexts["Profiles and roles"].exists)

        tap("setup.primary", in: app)
        waitFor(app.staticTexts["Choose a 4-digit PIN"])
        shot("12-perch-pin-new")
        enterPIN("1111", in: app)
        waitFor(app.staticTexts["Enter it again to confirm"])
        shot("13-perch-pin-confirm")
        enterPIN("2222", in: app)
        let error = element(app, "pinEntry.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(text(error), "Those PINs don't match")
        XCTAssertFalse(app.staticTexts["Enter it again to confirm"].exists, "a mismatch returns to choosing a PIN")
        XCTAssertFalse(app.staticTexts["Profiles and roles"].exists, "a mismatch does not move on")
        shot("14-perch-pin-mismatch")

        // Try again, matching this time.
        enterPIN("1111", in: app)
        waitFor(app.staticTexts["Enter it again to confirm"])
        enterPIN("1111", in: app)
        waitFor(app.staticTexts["Profiles and roles"], timeout: 15)

        tap("setup.primary", in: app)
        waitFor(app.staticTexts["More to add later"])
        tap("setup.primary", in: app)
        waitFor(app.staticTexts["You're all set"])
        tap("setup.primary", in: app)
        reachPicker(app)
        waitFor(element(app, "profile.1003"))
    }

    /// Setup complete but the Plex sign-in gone: the wizard runs again from Connect Plex (setup stays complete).
    @MainActor
    func testSignedOutAfterSetupReopensWizardAtConnectPlex() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        app.terminate()
        app.launchArguments = ["-PerchFakeHousehold", Household.noPINs.rawValue, "-PerchFakeSignedOut"]
        app.launch()

        waitFor(element(app, "root.reconnect"), timeout: 20)
        waitFor(app.staticTexts["Connect Plex"])
        XCTAssertFalse(app.staticTexts["Welcome to Perch"].exists, "setup is complete: no Welcome")
        tap("setup.primary", in: app)  // Sign in with a code
        waitFor(element(app, "setup.code.value"))
        XCTAssertTrue(waitUntil(10) { self.text(self.element(app, "setup.code.value")) == "PRCH" })
        shot("18-reconnect-link-code")
    }

    /// Five wrong Admin PINs in the wizard lock the step.
    @MainActor
    func testFiveWrongAdminPINsLockTheWizardStep() throws {
        let app = launchApp(.withPINs)
        try walkToAdminPIN(app, shots: false)
        tap("setup.primary", in: app)
        waitFor(element(app, "pinPad.1"))

        enterPIN("1111", in: app)
        let error = element(app, "pinEntry.error")
        waitFor(error)
        XCTAssertEqual(text(error), "That PIN isn't right")
        shot("15-admin-pin-wrong")

        for _ in 0..<4 {
            // After a wrong PIN the pad clears; wait for the spinner/error to settle then try again.
            enterPIN("1111", in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            if element(app, "setup.admin.message").exists { break }
        }

        let message = element(app, "setup.admin.message")
        waitFor(message, timeout: 15, "the lockout returns to the intro with a message")
        XCTAssertTrue(text(message).hasPrefix("Too many tries"), "got '\(text(message))'")
        XCTAssertFalse(app.staticTexts["Profiles and roles"].exists, "locked out, not through")
        shot("16-admin-pin-locked")
    }

    /// Back goes one step back: from a sub-screen, a PIN screen and a middle step.
    @MainActor
    func testBackReturnsToThePreviousStep() throws {
        let app = launchApp(.withPINs)
        waitFor(app.staticTexts["Welcome to Perch"])
        tap("setup.primary", in: app)
        waitFor(app.staticTexts["Connect Plex"])
        tap("setup.primary", in: app)
        waitFor(element(app, "setup.code.value"))

        // Code screen -> choice.
        back()
        waitFor(app.staticTexts["Connect Plex"])
        XCTAssertFalse(element(app, "setup.code.value").exists)

        // Choice -> Welcome.
        back()
        waitFor(app.staticTexts["Welcome to Perch"])

        // Forward again to the Admin PIN, then PIN entry -> Admin intro.
        tap("setup.primary", in: app)
        waitFor(app.staticTexts["Connect Plex"])
        tap("setup.primary", in: app)
        try waitConnected(app)
        tap("setup.primary", in: app)
        waitFor(element(app, "setup.admin.status"))
        tap("setup.primary", in: app)
        waitFor(element(app, "pinPad.1"))
        back()
        waitFor(element(app, "setup.admin.status"))
        XCTAssertFalse(element(app, "pinPad.1").exists)

        // Middle step: Admin intro -> Plex is connected.
        back()
        waitFor(element(app, "setup.connected.summary"))

        // And forward through the PIN to Profiles, then Back -> the confirmed Admin PIN step.
        tap("setup.primary", in: app)
        waitFor(element(app, "setup.admin.status").exists ? element(app, "setup.admin.status") : app.buttons["Use your Plex PIN"])
        tap("setup.primary", in: app)
        waitFor(element(app, "pinPad.1"))
        enterPIN(fakePlexPIN, in: app)
        waitFor(app.staticTexts["Profiles and roles"], timeout: 15)
        back()
        waitFor(app.staticTexts["Admin PIN confirmed"])
        shot("17-admin-pin-confirmed")
    }
}
