import XCTest

/// WP-07: playback through the real PlaybackCoordinator on the fake household (the bundled 60 s clip,
/// the fake episode "2101" with intro 5 to 15 s, final credits at 45 s and a saved offset of 20 s).
/// `player.status` (DEBUG) reads "<phase> pos=<s> skip=<intro|credits|none> upnext=<shown|none> overlay=<...>".
final class PlayerUITests: XCTestCase {
    private let episode = "2101"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Completes setup once (signed in, owner profile), then relaunches with `extra` and no reset.
    @MainActor
    private func signedIn(_ extra: [String] = []) throws -> XCUIApplication {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        if element(app, "root.picker").exists { pickProfile(1001, app) }
        waitFor(element(app, "home.profileName"), timeout: 20)
        guard !extra.isEmpty else { return app }
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "-PerchResetSetup" } + extra
        app.launch()
        return app
    }

    private func status(_ app: XCUIApplication) -> String { text(element(app, "player.status")) }

    private func position(_ app: XCUIApplication) -> Int {
        status(app).split(separator: " ").first { $0.hasPrefix("pos=") }.flatMap { Int($0.dropFirst(4)) } ?? -1
    }

    @MainActor
    private func expectStatus(_ app: XCUIApplication, contains part: String, timeout: TimeInterval = 15, _ why: String) {
        XCTAssertTrue(waitUntil(timeout) { self.status(app).contains(part) }, "\(why): status was '\(status(app))'")
    }

    @MainActor
    private func openLibraryCheck(_ app: XCUIApplication) {
        tap("placeholder.libraryCheck", in: app)
        waitFor(element(app, "libraryCheck.title"))
    }

    private func attach(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPlayFromLibraryCheckAndMenuReturnsToPlayButton() throws {
        let app = try signedIn()
        openLibraryCheck(app)
        let play = element(app, "libraryCheck.play.\(episode)")
        tap("libraryCheck.play.\(episode)", in: app)
        waitFor(element(app, "player.status"), timeout: 20)
        expectStatus(app, contains: "playing", "episode should start")
        for _ in 1...3 {
            XCUIRemote.shared.press(.menu)
            if waitForGone(element(app, "player.status"), timeout: 3) { break }
        }
        XCTAssertTrue(waitForGone(element(app, "player.status"), timeout: 5), "Menu should leave the player")
        XCTAssertTrue(waitUntil(8) { play.hasFocus }, "focus should return to the Play button")
    }

    @MainActor
    func testLaunchItemResumesInsideTheClip() throws {
        let app = try signedIn(["-PerchPlayItem", episode])
        waitFor(element(app, "player.status"), timeout: 25)
        expectStatus(app, contains: "playing", "episode should start")
        XCTAssertTrue(waitUntil(5) { self.position(app) >= 18 }, "should resume near 20 s, status '\(status(app))'")
    }

    @MainActor
    func testStillWatchingContinueKeepsPlaying() throws {
        let app = try signedIn(["-PerchPlayItem", episode, "-PerchForceOverlay", "stillWatching"])
        let continueButton = element(app, "player.stillWatching.continue")
        waitFor(continueButton, timeout: 40)
        XCTAssertTrue(waitUntil(5) { continueButton.hasFocus }, "Continue should have focus")
        attach("player-still-watching")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForGone(continueButton, timeout: 5), "Select should dismiss the overlay")
        expectStatus(app, contains: "overlay=none", "overlay cleared")
        XCTAssertTrue(element(app, "player.status").exists, "playback should continue (next episode)")
        expectStatus(app, contains: "playing", "playback should continue")
    }

    @MainActor
    func testStillWatchingStopExitsPlayer() throws {
        let app = try signedIn(["-PerchPlayItem", episode, "-PerchForceOverlay", "stillWatching"])
        let stop = element(app, "player.stillWatching.stop")
        waitFor(stop, timeout: 40)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitUntil(5) { stop.hasFocus }, "Stop should take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForGone(element(app, "player.status"), timeout: 8), "Stop should leave the player")
    }

    @MainActor
    func testCouldntPlayBackExitsPlayer() throws {
        let app = try signedIn(["-PerchPlayItem", episode, "-PerchForceOverlay", "failed"])
        let back = element(app, "player.failed.back")
        waitFor(element(app, "player.failed.retry"), timeout: 40)
        XCTAssertTrue(waitUntil(5) { self.element(app, "player.failed.retry").hasFocus }, "Try again should have focus")
        attach("player-failed")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitUntil(5) { back.hasFocus }, "Back should take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForGone(element(app, "player.status"), timeout: 8), "Back should leave the player")
    }
}
