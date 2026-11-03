import XCTest

/// WP-05 acceptance, picker side: profile PINs, the leave-a-kid rule, the kid refusal, lockout and the
/// offline picker. Each test runs the wizard first on the DEBUG fake household (`-PerchResetSetup`).
final class ProfilePickerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func openPicker(_ app: XCUIApplication) {
        reachPicker(app)
    }

    @MainActor
    private func waitForHome(_ app: XCUIApplication, as name: String) {
        let label = element(app, "home.profileName")
        waitFor(label, timeout: 15)
        XCTAssertTrue(waitUntil(10) { self.text(label) == "Watching as \(name)" }, "home shows \(name), got '\(text(label))'")
    }

    /// A protected profile asks for its PIN: wrong stays with an error, right switches.
    @MainActor
    func testProtectedProfileAsksForItsPIN() throws {
        let app = launchApp(.withPINs)
        try completeWizard(app, .withPINs)
        openPicker(app)
        shot("20-picker")

        tap("profile.1002", in: app)  // Jo, protected
        waitFor(element(app, "pinPad.1"))
        XCTAssertTrue(app.staticTexts["Enter Jo's PIN"].exists)
        shot("21-picker-pin")

        enterPIN("1111", in: app)
        expectPINError("That PIN isn't right", in: app)
        XCTAssertTrue(element(app, "pinPad.1").exists, "a wrong PIN stays on the PIN screen")
        shot("22-picker-pin-wrong")

        enterPIN(fakePlexPIN, in: app)
        waitForHome(app, as: "Jo")
        shot("23-home-as-jo")
    }

    /// Back from the PIN screen returns to the picker, nothing switched.
    @MainActor
    func testBackFromPINScreenReturnsToPicker() throws {
        let app = launchApp(.withPINs)
        try completeWizard(app, .withPINs)
        openPicker(app)
        tap("profile.1002", in: app)
        let key = element(app, "pinPad.1")
        waitFor(key)
        // Back before the pad has focus would leave the app: wait for focus first.
        XCTAssertTrue(waitUntil(5) { key.hasFocus }, "the PIN pad takes focus")
        back()
        waitFor(element(app, "picker.title"))
        XCTAssertFalse(key.exists)
        XCTAssertTrue(element(app, "profile.1002").exists)
    }

    /// Five wrong PINs on a protected profile lock it.
    @MainActor
    func testFiveWrongProfilePINsLock() throws {
        let app = launchApp(.withPINs)
        try completeWizard(app, .withPINs)
        openPicker(app)
        tap("profile.1002", in: app)
        waitFor(app.buttons["1"].firstMatch)

        var locked = false
        for _ in 0..<6 {
            enterPIN("1111", in: app)
            if waitUntil(4, { self.element(app, "pinEntry.locked").exists }) {
                locked = true
                break
            }
        }
        XCTAssertTrue(locked, "five wrong PINs lock the profile")
        XCTAssertTrue(text(element(app, "pinEntry.locked")).hasPrefix("Try again in"), "a countdown shows")
        shot("24-picker-pin-locked")
    }

    /// Back on the picker opened from home returns home (never drops the user elsewhere).
    @MainActor
    func testBackOnPickerOpenedFromHomeReturnsHome() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        openPicker(app)
        tap("profile.1001", in: app)
        waitForHome(app, as: "Robin")
        tap("home.switchProfile", in: app)
        let title = element(app, "picker.title")
        waitFor(title)
        let first = element(app, "profile.1001")
        waitFor(first)
        XCTAssertTrue(waitUntil(5) { first.hasFocus }, "the picker takes focus")
        back()
        waitForHome(app, as: "Robin")
        XCTAssertFalse(title.exists, "the picker is closed")
    }

    /// After five wrong PINs, leaving and reopening the PIN screen shows the locked state at once.
    @MainActor
    func testLockoutShowsAtOnceWhenPINScreenReopens() throws {
        let app = launchApp(.withPINs)
        try completeWizard(app, .withPINs)
        openPicker(app)
        tap("profile.1002", in: app)
        waitFor(app.buttons["1"].firstMatch)

        var locked = false
        for _ in 0..<6 {
            enterPIN("1111", in: app)
            if waitUntil(4, { self.element(app, "pinEntry.locked").exists }) {
                locked = true
                break
            }
        }
        XCTAssertTrue(locked, "five wrong PINs lock the profile")

        back()
        waitFor(element(app, "picker.title"))
        tap("profile.1002", in: app)
        // No further try: the locked state is there as soon as the screen is.
        let lockedAgain = element(app, "pinEntry.locked")
        waitFor(lockedAgain, timeout: 3)
        XCTAssertTrue(text(lockedAgain).hasPrefix("Try again in"), "a countdown shows on reopening")
        shot("24b-picker-pin-locked-reopened")
    }

    /// Leaving a kid profile asks for the Admin PIN even when the adult has no Plex PIN.
    @MainActor
    func testLeavingAKidProfileAsksForTheAdminPIN() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        openPicker(app)

        tap("profile.1003", in: app)  // Sam, kid: no PIN to go in
        waitForHome(app, as: "Sam")
        shot("25-home-as-sam")

        tap("home.switchProfile", in: app)
        waitFor(element(app, "picker.title"))
        shot("26-picker-as-sam")

        // Staying as Sam needs nothing and returns home.
        tap("profile.1003", in: app)
        waitForHome(app, as: "Sam")
        XCTAssertFalse(element(app, "pinPad.1").exists)

        // Robin has no Plex PIN, but leaving a kid asks for the Admin PIN.
        tap("home.switchProfile", in: app)
        waitFor(element(app, "picker.title"))
        tap("profile.1001", in: app)
        waitFor(element(app, "pinPad.1"))
        XCTAssertTrue(app.staticTexts["Enter the Admin PIN"].exists)
        shot("27-admin-pin-to-leave-kid")

        enterPIN("2222", in: app)
        expectPINError("That PIN isn't right", in: app)

        enterPIN(adminPerchPIN, in: app)
        waitForHome(app, as: "Robin")
    }

    /// A kid session cannot re-run setup, whatever PIN is typed.
    @MainActor
    func testKidCannotRunSetupAgain() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        openPicker(app)
        tap("profile.1003", in: app)
        waitForHome(app, as: "Sam")

        tap("home.runSetup", in: app)
        let refusal = element(app, "home.setupRefused")
        waitFor(refusal)
        XCTAssertEqual(text(refusal), "Ask a parent to change setup")
        XCTAssertFalse(element(app, "pinPad.1").exists, "a kid is not offered a keypad")
        XCTAssertFalse(element(app, "root.rerun").exists, "setup did not open")
        shot("28-kid-refused-setup")
        tap("home.setupRefused.ok", in: app)
        waitForHome(app, as: "Sam")
    }

    /// A parent can re-run setup with the Admin PIN (the other half of the gate).
    @MainActor
    func testParentRunsSetupAgainWithTheAdminPIN() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        // The wizard ends on the picker; choosing the current profile (Robin) goes home with no PIN.
        openPicker(app)
        tap("profile.1001", in: app)
        XCTAssertFalse(element(app, "pinPad.1").exists)
        waitForHome(app, as: "Robin")
        tap("home.runSetup", in: app)
        waitFor(element(app, "home.setupPIN"))
        shot("29-rerun-admin-pin")
        enterPIN(adminPerchPIN, in: app)
        waitFor(element(app, "root.rerun"), timeout: 15)
        waitFor(app.staticTexts["Welcome to Perch"])
    }

    /// With plex.tv unreachable the picker still shows the household, says it cannot switch, and keeps the profile.
    @MainActor
    func testOfflinePickerShowsProfilesAndCannotSwitch() throws {
        var app = launchApp(.withPINs)
        try completeWizard(app, .withPINs)

        app = relaunch(app, plexTVDown: true)
        waitForHome(app, as: "Robin")
        tap("home.switchProfile", in: app)
        waitFor(element(app, "picker.title"))
        for id in ["profile.1001", "profile.1002", "profile.1003"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), "\(id) shown from the cache")
        }
        let offline = element(app, "picker.offline")
        waitFor(offline, timeout: 15)
        XCTAssertEqual(text(offline), "Can't switch profiles right now")
        XCTAssertTrue(app.buttons["Try again"].exists, "offline offers Try again")
        shot("30-picker-offline")

        tap("profile.1003", in: app)
        let notice = element(app, "picker.notice")
        waitFor(notice)
        XCTAssertEqual(text(notice), "Can't switch profiles right now")
        shot("31-picker-offline-notice")

        // The current profile stays.
        back()
        waitForHome(app, as: "Robin")
    }
}
