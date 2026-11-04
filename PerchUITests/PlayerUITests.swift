import XCTest

/// WP-07: playback through the real PlaybackCoordinator on the fake household (the bundled 60 s clip,
/// the fake episode "2101" with intro 5 to 15 s, final credits at 45 s and a saved offset of 20 s).
/// `player.status` (DEBUG) reads "<phase> pos=<s> skip=<intro|credits|none> upnext=<shown|none> overlay=<...>
/// item=<rating key> items=<started> chain=<automatic advances in a row>". The fake series has E3 (2101), E4 (2102),
/// E5 (2104) and E6 (2105), all playing the clip.
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

    /// Presses Menu until the player closes (at most 4) and asserts it took exactly `presses`. A screenshot
    /// before each press shows which chrome took it (AVKit's chrome is not in the accessibility tree).
    @MainActor
    private func leaveWithMenu(_ app: XCUIApplication, presses: Int, _ state: String) {
        let probe = element(app, "player.status")
        var took = 0
        for press in 1...4 {
            shot("menu-\(state)-before-\(press)")
            XCUIRemote.shared.press(.menu)
            if waitForGone(probe, timeout: press < presses ? 2.5 : 5) {
                took = press
                break
            }
        }
        XCTAssertEqual(took, presses, "\(state): Menu presses to leave the player (0 = still up after 4)")
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
        // AVKit shows its title and transport bar when an item starts; with no input it hides them again.
        // Resumed at 20 s, so by 32 s (past the intro, before the credits) no chrome shows: one Menu leaves.
        XCTAssertTrue(waitUntil(20) { self.position(app) >= 32 }, "should play past 32 s, status '\(status(app))'")
        leaveWithMenu(app, presses: 1, "no-chrome")
        XCTAssertTrue(waitUntil(8) { play.hasFocus }, "focus should return to the Play button")
    }

    @MainActor
    func testLaunchItemResumesInsideTheClip() throws {
        let app = try signedIn(["-PerchPlayItem", episode])
        waitFor(element(app, "player.status"), timeout: 25)
        expectStatus(app, contains: "playing", "episode should start")
        XCTAssertTrue(waitUntil(5) { self.position(app) >= 18 }, "should resume near 20 s, status '\(status(app))'")
        // Paused: AVKit's transport bar is up and stays up. The first Menu hides it, the second leaves.
        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "paused", "play/pause should pause")
        leaveWithMenu(app, presses: 2, "transport-bar")
    }

    /// The real "Are you still watching?" path, unforced: with the chain limit at 2 and a 2 s countdown,
    /// E3 and E4 advance by themselves at the credits; E5 shows no proposal and its end asks once.
    @MainActor
    func testRealChainAdvancesTwiceThenAsksStillWatchingOnce() throws {
        let app = try signedIn([
            "-PerchPlayItem", episode, "-PerchStartMs", "40000", "-PerchChainStartMs", "40000",
            "-PerchPolicy", "upNextCountdown=2,stillWatchingAfter=2",
        ])
        waitFor(element(app, "player.status"), timeout: 25)
        expectStatus(app, contains: "item=2101 items=1 chain=0", "first episode")
        // No remote presses until the prompt: any input resets the chain.
        expectStatus(app, contains: "item=2102 items=2 chain=1", timeout: 30, "the countdown should advance to E4")
        expectStatus(app, contains: "item=2104 items=3 chain=2", timeout: 30, "the countdown should advance to E5")

        var sawProposal = false
        let raised = waitUntil(45) {
            let now = self.status(app)
            if now.contains("upnext=shown") { sawProposal = true }
            return now.contains("overlay=stillWatching")
        }
        XCTAssertTrue(raised, "the end of E5 should ask: status '\(status(app))'")
        XCTAssertFalse(sawProposal, "no up next proposal at the chain limit")
        let continueButton = element(app, "player.stillWatching.continue")
        waitFor(continueButton, timeout: 5)
        let prompts = app.descendants(matching: .any).matching(identifier: "player.stillWatching.continue").count
        XCTAssertEqual(prompts, 1, "exactly one still-watching prompt")
        expectStatus(app, contains: "upnext=none overlay=stillWatching item=2104 items=3 chain=2", "nothing advanced")
        XCTAssertTrue(waitUntil(5) { continueButton.hasFocus }, "Continue should have focus")
        attach("v2-still-watching")

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForGone(continueButton, timeout: 5), "Select should dismiss the prompt")
        expectStatus(app, contains: "overlay=none item=2105 items=4 chain=0", "Continue plays E6 with the chain reset")
        expectStatus(app, contains: "playing", "E6 should play")

        // The native controls are back and have the remote: play/pause works, Down opens the info panel.
        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "paused", "play/pause should reach the player after Continue")
        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "playing", "play/pause should resume")
        attach("v2-after-continue")
        XCUIRemote.shared.press(.down)
        attach("v2-after-continue-info")
        XCTAssertTrue(element(app, "player.status").exists, "still in the player")
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
        attach("v2-failed")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitUntil(5) { back.hasFocus }, "Back should take focus")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForGone(element(app, "player.status"), timeout: 8), "Back should leave the player")
    }
}
