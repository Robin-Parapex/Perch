import XCTest

/// WP-07 spike: the overlay window above an embedded AVPlayerViewController. Plays the DEBUG clip via
/// `-PerchPlayerSpike local` (no server, no sign-in). The status label reads
/// "<playing|paused> overlay=<shown|none> key=<main|overlay> actions=<n> item=<n> skip=<intro|credits|none>
/// upnext=<shown|none> advances=<n>". Playback runs through the real PlaybackSession and NativeEngine.
final class PlayerSpikeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchSpike() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchPlayerSpike", "local"]
        app.launch()
        return app
    }

    private func status(_ app: XCUIApplication) -> String { text(element(app, "spike.status")) }

    @MainActor
    private func expectStatus(_ app: XCUIApplication, contains part: String, timeout: TimeInterval = 8, _ why: String) {
        XCTAssertTrue(waitUntil(timeout) { self.status(app).contains(part) }, "\(why): status was '\(status(app))'")
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// (a) A passive overlay shows above the video and the remote still drives the player.
    @MainActor
    func testPassiveOverlayLeavesRemoteWithPlayer() {
        let app = launchSpike()
        tap("spike.play.passive", in: app)
        waitFor(element(app, "spike.status"), timeout: 15)
        expectStatus(app, contains: "playing", "clip should start")
        waitFor(element(app, "overlay.passive"), timeout: 5)
        expectStatus(app, contains: "key=main", "passive overlay must not become key")
        shot("q1a-passive-playing")

        // Native Skip Intro (AVKit contextual action) from the session while the passive window is up: it
        // exists only inside the fake intro (5 to 15 s), so check it first. Select takes it (seek to 15.5 s).
        expectStatus(app, contains: "skip=intro", timeout: 10, "Skip Intro should be offered in the intro")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("q1a-contextual-action")
        XCUIRemote.shared.press(.select)
        expectStatus(app, contains: "actions=1", "contextual action Select should fire")
        expectStatus(app, contains: "skip=none", "Skip Intro gone after the skip")
        expectStatus(app, contains: "playing", "skipping must not pause")
        shot("q1a-after-contextual-select")

        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "paused", "play/pause should reach the player")
        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "playing", "play/pause again should resume")

        // Down opens the player's info panel (AVKit's UI is not in the accessibility tree: screenshot proof).
        XCUIRemote.shared.press(.down)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("q1a-info-panel")
        XCTAssertTrue(element(app, "overlay.passive").exists, "passive overlay should still show")
        // Menu closes the panel (the player handles it), it does not leave the player.
        XCUIRemote.shared.press(.menu)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertTrue(element(app, "spike.status").exists, "Menu with the info panel up must stay in the player")
        shot("q1a-info-panel-closed")
    }

    /// (b) focus overlay takes focus and Select fires; (c) Menu closes it and the player gets the remote back;
    /// (d) Menu on the player exits to the launching screen with focus on the launching button.
    @MainActor
    func testFocusOverlayHandsFocusBackAndMenuExits() {
        let app = launchSpike()
        tap("spike.play.focus", in: app)
        waitFor(element(app, "spike.status"), timeout: 15)
        expectStatus(app, contains: "playing", "clip should start")

        let skip = element(app, "overlay.skip")
        waitFor(skip, timeout: 10)
        expectStatus(app, contains: "key=overlay", "focus overlay should become key")
        XCTAssertTrue(waitUntil(5) { skip.hasFocus }, "Skip Intro should be focused")
        shot("q1b-focus-overlay")
        XCUIRemote.shared.press(.select)
        expectStatus(app, contains: "actions=1", "Select should fire the overlay action")
        expectStatus(app, contains: "playing", "select on the overlay must not pause the player")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForGone(skip, timeout: 5), "Menu should close the overlay")
        expectStatus(app, contains: "overlay=none key=main", "key should return to the app window")
        XCTAssertTrue(element(app, "spike.status").exists, "Menu on the overlay must not leave the player")
        shot("q1c-after-overlay")

        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "paused", "player transport should work again")
        XCUIRemote.shared.press(.playPause)
        expectStatus(app, contains: "playing", "and resume")

        // (d) Menu with no overlay: AVKit takes one press to hide the transport bar and, inside the fake
        // intro, one to put away the Skip Intro action; the next leaves the player.
        for press in 1...3 {
            XCUIRemote.shared.press(.menu)
            if waitForGone(element(app, "spike.status"), timeout: 3) { break }
            dump(app, "q1d-after-menu-\(press)")
            shot("q1d-after-menu-\(press)")
        }
        XCTAssertTrue(waitForGone(element(app, "spike.status"), timeout: 5), "Menu should leave the player")
        XCTAssertTrue(waitUntil(5) { self.text(self.element(app, "spike.exits")) == "Exits: 1" })
        let launcher = element(app, "spike.play.focus")
        XCTAssertTrue(waitUntil(5) { launcher.hasFocus }, "focus should return to the launching button")
        shot("q1d-back-on-launcher")
    }

    /// (e) Real PlaybackSession through NativeEngine: resume at 0:40, AVKit's content proposal appears at
    /// the fake final credits (45 s), its countdown accepts at 0 and the next item loads in the same engine.
    @MainActor
    func testUpNextCountdownAdvancesToNextItem() {
        let app = launchSpike()
        tap("spike.play.upnext", in: app)
        waitFor(element(app, "spike.status"), timeout: 15)
        expectStatus(app, contains: "playing", "clip should start")
        expectStatus(app, contains: "item=1", "first item")
        // Credits start 5 s after the resume point; the proposal follows within a second.
        expectStatus(app, contains: "upnext=shown", timeout: 12, "up next proposal should be on screen")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        shot("q1e-up-next-countdown")
        // Ten-second countdown, then the same engine loads the next item.
        expectStatus(app, contains: "item=2", timeout: 15, "countdown should accept and load the next item")
        expectStatus(app, contains: "advances=1", "a countdown accept is an automatic advance")
        expectStatus(app, contains: "playing", "next item should play")
        expectStatus(app, contains: "upnext=none", "proposal gone")
        shot("q1e-next-item")

        // As (d): the transport bar and, inside the intro, Skip Intro each take one Menu first.
        for press in 1...3 {
            XCUIRemote.shared.press(.menu)
            if waitForGone(element(app, "spike.status"), timeout: 3) { break }
            shot("q1e-after-menu-\(press)")
        }
        XCTAssertTrue(waitForGone(element(app, "spike.status"), timeout: 5), "Menu should leave the player")
        XCTAssertTrue(waitUntil(5) { self.text(self.element(app, "spike.exits")) == "Exits: 1" })
    }
}
