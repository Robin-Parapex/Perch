import XCTest

/// WP-12: Search on the DEBUG fake household (noPINs). The fake server matches titles by case-insensitive substring:
/// "harbour" finds the films Harbour Lights (1001), Midnight Ferry is not among them; series Bright Harbour (2202),
/// Cold Harbour Files (3000) and 24 Hours in Harbour (2208); the collection Harbour stories (9001). Sam (1003) is a
/// little_kid. Dictation cannot be automated: holding the Siri button in the field is a manual check.
final class SearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Films and series rated 15 or 18 in the fake catalogue (what a kid must never see).
    private static let adultOnly: Set<String> = [
        "1007", "1009", "1011", "1016", "1018", "1022", "1026", "1027", "2204", "2206", "2209",
    ]

    // MARK: Helpers

    /// Screenshot as an attachment, and to `PERCH_SHOT_DIR` when the runner has it (`TEST_RUNNER_PERCH_SHOT_DIR`).
    @MainActor
    private func capture(_ name: String) {
        shot(name)
        if let folder = ProcessInfo.processInfo.environment["PERCH_SHOT_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
    }

    /// Wizard, profile, then the Search tab with focus in its field.
    @MainActor
    private func openSearch(profile: Int = 1001, extraArguments: [String] = []) throws -> XCUIApplication {
        let app = launchApp(.noPINs, extraArguments: ["-PerchUITests"] + extraArguments)
        try completeWizard(app, .noPINs)
        if profile != 1001 {
            reachPicker(app)
            pickProfile(profile, app)
        } else if element(app, "root.picker").exists {
            pickProfile(profile, app)
        }
        waitFor(element(app, "home.root"), timeout: 20)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        selectTab("Search", app)
        waitFor(element(app, "search.root"), timeout: 10)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    @MainActor
    private func selectTab(_ label: String, _ app: XCUIApplication) {
        openSidebar(app)
        XCTAssertTrue(focus(sidebarTab(app, label), in: app), "\(label) in the sidebar")
        XCUIRemote.shared.press(.select)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    @MainActor
    private func field(_ app: XCUIApplication) -> XCUIElement { app.searchFields.firstMatch }

    @MainActor
    private func type(_ text: String, _ app: XCUIApplication) {
        let field = field(app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field shows")
        field.typeText(text)
    }

    @MainActor
    private func resultIDs(_ app: XCUIApplication) -> Set<String> {
        let items = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'search.item.'"))
            .allElementsBoundByIndex
        return Set(items.map { $0.identifier.replacingOccurrences(of: "search.item.", with: "") })
    }

    // MARK: Tests

    /// Type with the keyboard, see results; Select a film opens its page and Back lands on the same result; leaving
    /// the tab and returning keeps the query and the results.
    @MainActor
    func testTypeSelectBackAndReturnToTab() throws {
        let app = try openSearch()
        // Nothing typed: Home's Recently added under the keyboard, no hint.
        waitFor(element(app, "search.row.recent"), timeout: 5, "Recently added with nothing typed")
        XCTAssertFalse(element(app, "search.hint").exists)
        capture("wp12b-empty")

        type("harbour", app)
        waitFor(element(app, "search.item.1001"), timeout: 10, "results appear")
        XCTAssertTrue(element(app, "search.row.films").exists)
        XCTAssertTrue(element(app, "search.row.series").exists)
        XCTAssertTrue(resultIDs(app).isSuperset(of: ["1001", "2202", "3000", "2208"]), "\(resultIDs(app))")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        capture("wp12b-results")

        // Select a film: its title page; Back returns to the same result.
        XCTAssertTrue(focus(element(app, "search.item.1001"), in: app), "the film result takes focus")
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "title.primary"), timeout: 10, "the film's page opens")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        back()
        waitFor(element(app, "search.item.1001"), timeout: 10)
        XCTAssertTrue(waitUntil(5) { self.element(app, "search.item.1001").hasFocus }, "Back lands on the same result")

        // Leave the tab and come back: query and results are still there.
        selectTab("Home", app)
        waitFor(element(app, "home.root"), timeout: 10)
        selectTab("Search", app)
        waitFor(element(app, "search.item.1001"), timeout: 10, "results are kept")
        XCTAssertEqual(field(app).value as? String, "harbour", "the query is kept")
    }

    /// Play/Pause on a result plays it; Back from the player returns focus to the same card (review finding).
    @MainActor
    func testPlayFromSearchAndBackReturnsToTheCard() throws {
        let app = try openSearch()
        type("harbour", app)
        waitFor(element(app, "search.item.1001"), timeout: 10, "results appear")
        XCTAssertTrue(focus(element(app, "search.item.1001"), in: app), "the film result takes focus")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitUntil(10) { !self.element(app, "search.root").isHittable }, "the player opens")
        // Menu until Search shows again (the player may first close its transport bar or finish loading).
        for _ in 0..<4 {
            back()
            if waitUntil(4, { self.element(app, "search.root").isHittable }) { break }
        }
        XCTAssertTrue(element(app, "search.root").isHittable, "Search is visible again after Back")
        XCTAssertTrue(waitUntil(6) { self.element(app, "search.item.1001").hasFocus }, "Back from the player lands on the same card")
    }

    /// A query nothing matches: the calm message.
    @MainActor
    func testNoResultsMessage() throws {
        let app = try openSearch()
        type("zzqxv", app)
        waitFor(element(app, "search.noResults"), timeout: 10, "the no-results message")
        XCTAssertTrue(resultIDs(app).isEmpty)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        capture("wp12b-noresults")
    }

    /// A kid never sees a 15 or 18 title, even when the server leaks them (`-PerchFakeSearchIgnoresRestriction`).
    @MainActor
    func testKidNeverSeesAdultTitles() throws {
        let app = try openSearch(profile: 1003, extraArguments: ["-PerchFakeSearchIgnoresRestriction"])
        // A wide query: "o" matches U titles and 15/18 ones (Echo Valley, Copper Coast, Low Tide, Fogbound...).
        type("o", app)
        waitFor(element(app, "search.item.1015"), timeout: 10, "a U title shows (Kite Season)")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        let shown = resultIDs(app)
        XCTAssertTrue(shown.isDisjoint(with: Self.adultOnly), "adult titles shown to a kid: \(shown.intersection(Self.adultOnly))")
        XCTAssertFalse(element(app, "search.row.collections").exists, "no collections for a kid")
        capture("wp12b-kid")
    }
}
