import XCTest

/// WP-11: title and series pages on the DEBUG fake household (noPINs). Series 2000 "The Lantern Keepers" has two
/// seasons (S1 E3 = 2101 part watched and the latest viewing, S2 = 2121 to 2124) and a theme; film 1004 (U) has a
/// theme; film 1001 is part watched. Sam (1003) is a little_kid. With `TEST_RUNNER_PERCH_SHOT_DIR` set, the named
/// screenshots are also written there as PNG files. Theme music is off by default in 0.3; the theme tests pass
/// `-PerchThemeMusic` (DEBUG) to switch it on.
final class TitleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Helpers

    @MainActor
    private func reachHome(profile: Int = 1001, themeMusic: Bool = false) throws -> XCUIApplication {
        let app = launchApp(.noPINs, extraArguments: ["-PerchUITests"] + (themeMusic ? ["-PerchThemeMusic"] : []))
        try completeWizard(app, .noPINs)
        if profile != 1001 {
            reachPicker(app)
            pickProfile(profile, app)
        } else if element(app, "root.picker").exists {
            pickProfile(profile, app)
        }
        waitFor(element(app, "home.root"), timeout: 20)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    @MainActor
    private func openFilms(profile: Int = 1001, themeMusic: Bool = false) throws -> XCUIApplication {
        let app = try reachHome(profile: profile, themeMusic: themeMusic)
        openSidebar(app)
        XCTAssertTrue(focus(sidebarTab(app, "Films"), in: app), "Films in the sidebar")
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "library.grid"), timeout: 15, "the grid shows")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    @MainActor
    private func hasFocus(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 6) -> Bool {
        let target = element(app, id)
        return waitUntil(timeout) { target.hasFocus }
    }

    @MainActor
    private func focusedDescription(_ app: XCUIApplication) -> String {
        let all = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        guard let now = all.last(where: { $0.elementType != .window && $0.elementType != .other }) ?? all.last else { return "nothing" }
        return "\(now.elementType.rawValue) id=\(now.identifier) label=\(now.label)"
    }

    /// The theme marker's state ("playing", "off", "none", "stopped").
    @MainActor
    private func themeState(_ app: XCUIApplication) -> String {
        let marker = element(app, "title.theme")
        return marker.exists ? marker.label : "missing"
    }

    /// Attaches a screenshot and, when asked, writes it to the shot folder.
    @MainActor
    private func capture(_ name: String) {
        shot(name)
        if let folder = ProcessInfo.processInfo.environment["PERCH_SHOT_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
    }

    @MainActor
    private func backUntilHittable(_ app: XCUIApplication, _ id: String) {
        for _ in 0..<4 {
            back()
            if waitUntil(4, { self.element(app, id).isHittable }) { break }
        }
        XCTAssertTrue(element(app, id).isHittable, "\(id) visible again after Back")
    }

    // MARK: Tests

    @MainActor
    func testGridPosterOpensTitlePageAndBackReturnsToThePoster() throws {
        let app = try openFilms()
        XCTAssertTrue(focus(element(app, "library.item.1027"), in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "title.root"), timeout: 10, "Select opens the title page")
        XCTAssertTrue(hasFocus(app, "title.primary", timeout: 8), "the primary button has focus; focus: \(focusedDescription(app))")
        XCTAssertTrue(element(app, "title.primary").label.hasPrefix("Play"), "not started: Play")
        waitFor(element(app, "title.cast"), timeout: 8, "the cast rail")
        XCTAssertTrue(element(app, "title.watched").exists, "Mark watched")
        XCTAssertEqual(element(app, "title.watched").label, "Mark watched", "the icon button keeps its name")
        capture("wp11b-title")
        back()
        XCTAssertTrue(waitForGone(element(app, "title.root"), timeout: 6), "Back pops the page")
        XCTAssertTrue(hasFocus(app, "library.item.1027"), "Back lands on the same poster; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testHomeLongPressDetailsShowsResume() throws {
        let app = try reachHome()
        XCTAssertTrue(focus(element(app, "home.card.1001"), in: app))
        XCUIRemote.shared.press(.select, forDuration: 1.6)
        let details = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Details'")).firstMatch
        if !details.waitForExistence(timeout: 5) {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "longpress-tree"
            tree.lifetime = .keepAlways
            add(tree)
            shot("longpress-state")
        }
        waitFor(details, timeout: 1, "the long-press menu offers Details")
        XCTAssertTrue(focus(details, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "title.root"), timeout: 10)
        XCTAssertTrue(hasFocus(app, "title.primary", timeout: 8), "focus: \(focusedDescription(app))")
        let label = element(app, "title.primary").label
        XCTAssertTrue(label.hasPrefix("Resume") && label.contains("left"), "Resume with the time left: \(label)")
        XCTAssertTrue(element(app, "title.fromStart").exists, "Play from the start while resuming")
        capture("wp11b-title-resume")
        back()
        XCTAssertTrue(waitForGone(element(app, "title.root"), timeout: 6))
        XCTAssertTrue(hasFocus(app, "home.card.1001"), "Back lands on the card; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testHomeSeriesCardOpensSeriesPagePlaysAnEpisodeAndBackReturns() throws {
        let app = try reachHome(themeMusic: true)
        let card = element(app, "home.card.2000")
        waitFor(card, timeout: 10, "the series card in Recently added")
        XCTAssertTrue(focus(card, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "series.root"), timeout: 10, "Select on a series card opens its page")
        XCTAssertTrue(hasFocus(app, "series.primary", timeout: 8), "Play next has focus; focus: \(focusedDescription(app))")
        XCTAssertTrue(waitUntil(6) { self.element(app, "series.primary").label == "Resume, S1 E3" }, "label: \(element(app, "series.primary").label)")
        XCTAssertTrue(waitUntil(6) { self.themeState(app) == "playing" }, "the theme plays for an adult: \(themeState(app))")
        waitFor(element(app, "series.episode.2101"), timeout: 8, "season 1 opens on the next episode's season")
        XCTAssertFalse(element(app, "series.jumpNext").exists, "no jump chip on the next episode's own season")
        capture("wp11b-series")

        XCTAssertTrue(focus(element(app, "series.season.2"), in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "series.episode.2121"), timeout: 8, "season 2's episodes")
        XCTAssertFalse(element(app, "series.episode.2101").exists, "season 1's are gone")
        let jump = element(app, "series.jumpNext")
        waitFor(jump, timeout: 4, "another season shown: the jump chip to the next episode")
        XCTAssertTrue(jump.label.contains("S1 E3"), "jump label: \(jump.label)")
        let episode = element(app, "series.episode.2122")
        XCTAssertTrue(focus(episode, in: app))
        capture("wp11b-series-season2")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitUntil(10) { !self.element(app, "series.root").isHittable }, "the episode plays")
        XCTAssertTrue(waitUntil(4) { self.themeState(app) == "stopped" }, "playback stops the theme: \(themeState(app))")
        backUntilHittable(app, "series.root")
        XCTAssertTrue(hasFocus(app, "series.episode.2122", timeout: 8), "Back from the player lands on the episode; focus: \(focusedDescription(app))")
        back()
        XCTAssertTrue(waitForGone(element(app, "series.root"), timeout: 6), "Back pops the series page")
        XCTAssertTrue(hasFocus(app, "home.card.2000"), "then on the Home card; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testCollectionTitleOpensAndBackReturnsThroughTheCollection() throws {
        let app = try openFilms()
        let card = element(app, "library.collection.9002")
        waitFor(card, timeout: 10)
        XCTAssertTrue(focus(card, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "collection.root"), timeout: 10)
        let poster = element(app, "library.item.1003")
        waitFor(poster, timeout: 10)
        XCTAssertTrue(focus(poster, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "title.root"), timeout: 10, "a collection poster opens its title page")
        XCTAssertTrue(hasFocus(app, "title.primary", timeout: 8), "focus: \(focusedDescription(app))")
        back()
        XCTAssertTrue(waitForGone(element(app, "title.root"), timeout: 6))
        XCTAssertTrue(hasFocus(app, "library.item.1003"), "Back lands on the collection poster; focus: \(focusedDescription(app))")
        back()
        XCTAssertTrue(waitForGone(element(app, "collection.root"), timeout: 6))
        XCTAssertTrue(hasFocus(app, "library.collection.9002"), "then on the collection card; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testKidTitlePageHasNoTheme() throws {
        // The flag is on: a kid still never hears it.
        let app = try openFilms(profile: 1003, themeMusic: true)
        let poster = element(app, "library.item.1004")
        waitFor(poster, timeout: 10, "a U film with a theme")
        XCTAssertTrue(focus(poster, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "title.root"), timeout: 10)
        XCTAssertTrue(hasFocus(app, "title.primary", timeout: 8), "focus: \(focusedDescription(app))")
        waitFor(element(app, "title.cast"), timeout: 8)
        XCTAssertTrue(waitUntil(4) { self.themeState(app) == "off" }, "no theme for a kid: \(themeState(app))")
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(themeState(app), "off", "and it never starts")
        capture("wp11b-kid-title")
    }
}
