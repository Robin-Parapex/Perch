import XCTest

/// WP-10: Films on the DEBUG fake household (noPINs). Section 1 holds 28 films (1001 to 1028; sorted by recently
/// added the higher id comes first), collections 9001 "Harbour stories" and 9002 "Family nights". Sam (1003) is a
/// little_kid: the fake server shows him U titles only.
final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// U-rated films; everything else (PG, 12, 15, 18, unrated) is hidden from a little_kid.
    private static let kidFilms: Set<String> = ["1004", "1005", "1010", "1015", "1020", "1028"]
    private static let adultOnlyFilms: Set<String> = ["1007", "1009", "1011", "1016", "1018", "1022", "1026", "1027"]

    // MARK: Helpers

    /// Wizard, profile, then the Films tab with its grid on screen.
    @MainActor
    private func openFilms(profile: Int = 1001) throws -> XCUIApplication {
        let app = launchApp(.noPINs, extraArguments: ["-PerchUITests"])
        try completeWizard(app, .noPINs)
        if profile != 1001 {
            reachPicker(app)
            pickProfile(profile, app)
        } else if element(app, "root.picker").exists {
            pickProfile(profile, app)
        }
        waitFor(element(app, "home.root"), timeout: 20)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        openSidebar(app)
        XCTAssertTrue(focus(sidebarTab(app, "Films"), in: app), "Films in the sidebar")
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "library.root"), timeout: 10)
        waitFor(element(app, "library.grid"), timeout: 15, "the grid shows")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    @MainActor
    private func itemIDs(_ app: XCUIApplication) -> Set<String> {
        let items = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'"))
            .allElementsBoundByIndex
        return Set(items.map { $0.identifier.replacingOccurrences(of: "library.item.", with: "") })
    }

    @MainActor
    private func hasFocus(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 5) -> Bool {
        let target = element(app, id)
        return waitUntil(timeout) { target.hasFocus }
    }

    @MainActor
    private func focusedDescription(_ app: XCUIApplication) -> String {
        let all = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).allElementsBoundByIndex
        guard let now = all.last(where: { $0.elementType != .window && $0.elementType != .other }) ?? all.last else { return "nothing" }
        return "\(now.elementType.rawValue) id=\(now.identifier) label=\(now.label) frame=\(now.frame)"
    }

    /// Opens a header menu and chooses an entry (by identifier, else by its title).
    @MainActor
    private func choose(_ menuID: String, entry: String, title: String, shotName: String? = nil, in app: XCUIApplication) {
        tap(menuID, in: app)
        let byID = element(app, entry)
        let byTitle = app.buttons[title].firstMatch
        XCTAssertTrue(waitUntil(5) { byID.exists || byTitle.exists }, "menu entry \(title) shows")
        if let shotName { shot(shotName) }
        tap(byID.exists ? byID : byTitle, in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }

    /// Back out of the player until the grid is hittable again (the player may first close its own chrome).
    @MainActor
    private func backToLibrary(_ app: XCUIApplication) {
        for _ in 0..<4 {
            back()
            if waitUntil(4, { self.element(app, "library.root").isHittable }) { break }
        }
        XCTAssertTrue(element(app, "library.root").isHittable, "the grid is visible again after Back")
    }

    // MARK: Tests

    @MainActor
    func testGridSortByTitleShowsLettersAndJumpFocusesFirstTitle() throws {
        let app = try openFilms()
        XCTAssertTrue(focus(element(app, "library.item.1028"), in: app), "the newest film takes focus")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner on the grid")
        XCTAssertFalse(element(app, "library.letters").exists, "no letter rail unless sorted by title")
        shot("wp10b-grid")

        choose("library.sort", entry: "library.sort.title", title: "Title", in: app)
        waitFor(element(app, "library.letters"), timeout: 10, "the letter rail shows when sorted by title")
        XCTAssertTrue(element(app, "library.letter.#").exists, "a digit title gives a # bucket")
        XCTAssertTrue(hasFocus(app, "library.item.1004"), "a sort change focuses the first title; focus: \(focusedDescription(app))")

        // Right along the first row: past the last column it reaches the rail. Left goes back to the grid.
        let onRail = { () -> Bool in
            let letters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'library.letter.'"))
            return letters.allElementsBoundByIndex.contains { $0.hasFocus }
        }
        for _ in 0..<7 where !onRail() {
            XCUIRemote.shared.press(.right)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTAssertTrue(onRail(), "Right from the last column reaches the rail; focus: \(focusedDescription(app))")
        XCUIRemote.shared.press(.left)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(waitUntil(3) { !onRail() && self.focusedDescription(app).contains("library.item.") }, "Left returns to the grid; focus: \(focusedDescription(app))")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitUntil(3) { onRail() }, "and Right reaches the rail again")
        // Up or down the rail to M, one letter per press.
        let order = ["#"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        let present = order.filter { element(app, "library.letter.\($0)").exists }
        let letters = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'library.letter.'"))
        let current = letters.allElementsBoundByIndex.first { $0.hasFocus }?.identifier.replacingOccurrences(of: "library.letter.", with: "")
        let from = try XCTUnwrap(current.flatMap { present.firstIndex(of: $0) }, "a letter has focus")
        let to = try XCTUnwrap(present.firstIndex(of: "M"))
        for _ in 0..<abs(to - from) {
            XCUIRemote.shared.press(to > from ? .down : .up)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        XCTAssertTrue(hasFocus(app, "library.letter.M"), "M on the rail (from \(current ?? "?")); focus: \(focusedDescription(app))")
        shot("wp10b-letters")
        XCUIRemote.shared.press(.select)
        // Sorted by title, M starts with Marigold Station (1017); "The Hollow Road" sorts under H.
        XCTAssertTrue(hasFocus(app, "library.item.1017", timeout: 8), "the first M title has focus; focus: \(focusedDescription(app))")
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(hasFocus(app, "library.item.1018"), "the next title follows it")
    }

    @MainActor
    func testGenreAndUnwatchedFiltersThenClearAndEmptyResult() throws {
        let app = try openFilms()
        XCTAssertTrue(element(app, "library.item.1026").exists, "a thriller shows before filtering")
        choose("library.filter.genre", entry: "library.filter.genre.105", title: "Family", shotName: "wp10b-filters", in: app)
        XCTAssertTrue(waitUntil(8) { self.element(app, "library.item.1028").exists && !self.element(app, "library.item.1026").exists }, "Family only")
        XCTAssertTrue(element(app, "library.item.1010").exists, "a watched family film shows before Unwatched")
        XCTAssertTrue(element(app, "library.filter.clear").exists, "clear all shows with a filter set")

        tap("library.filter.unwatched", in: app)
        XCTAssertTrue(waitUntil(8) { !self.element(app, "library.item.1010").exists }, "Unwatched hides watched titles")
        XCTAssertTrue(element(app, "library.item.1028").exists)
        XCTAssertTrue(element(app, "library.filter.clear").label.contains("2"), "the clear chip counts two filters: \(element(app, "library.filter.clear").label)")

        tap("library.filter.clear", in: app)
        XCTAssertTrue(waitUntil(8) { self.element(app, "library.item.1026").exists }, "clear filters shows everything again")
        XCTAssertTrue(waitForGone(element(app, "library.filter.clear"), timeout: 5), "no clear chip without filters")

        // Documentary and SD match nothing.
        choose("library.filter.genre", entry: "library.filter.genre.107", title: "Documentary", in: app)
        choose("library.filter.resolution", entry: "library.filter.resolution.sd", title: "SD", in: app)
        waitFor(element(app, "library.message"), timeout: 8, "the no-match message")
        XCTAssertTrue(app.staticTexts["Nothing matches these filters"].exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
        shot("wp10b-empty")
        tap("library.empty.clear", in: app)
        XCTAssertTrue(waitUntil(8) { self.element(app, "library.item.1026").exists }, "Clear filters restores the grid")
    }

    @MainActor
    func testCollectionOpensAndBackReturnsToTheCard() throws {
        let app = try openFilms()
        let card = element(app, "library.collection.9002")
        waitFor(card, timeout: 10, "the Collections row shows")
        XCTAssertTrue(focus(card, in: app), "the Family nights card")
        shot("wp10b-collections-row")
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "collection.root"), timeout: 10)
        waitFor(element(app, "collection.hero"), timeout: 10, "the collection opens with its hero")
        waitFor(element(app, "library.item.1003"), timeout: 10, "the collection's titles")
        XCTAssertTrue(waitUntil(5) { self.itemIDs(app).contains("1011") }, "a 15 title shows for an adult")
        XCTAssertTrue(waitUntil(5) { self.element(app, "collection.count").label == "6 titles" }, "the title count")
        shot("wp10b-collection")
        back()
        XCTAssertTrue(waitForGone(element(app, "collection.root"), timeout: 5), "Back pops the collection")
        XCTAssertTrue(hasFocus(app, "library.collection.9002", timeout: 6), "Back lands on the same card; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testPosterPlaysAndBackReturnsToThePoster() throws {
        let app = try openFilms()
        XCTAssertTrue(focus(element(app, "library.item.1027"), in: app))
        // WP-11: Select opens the title page (TitleUITests); Play/Pause still plays from the grid.
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitUntil(10) { !self.element(app, "library.root").isHittable }, "the player opens")
        backToLibrary(app)
        XCTAssertTrue(hasFocus(app, "library.item.1027", timeout: 6), "Back lands on the same poster; focus: \(focusedDescription(app))")
    }

    @MainActor
    func testKidSeesNoFifteenOrEighteenTitles() throws {
        let app = try openFilms(profile: 1003)
        XCTAssertTrue(waitUntil(8) { !self.itemIDs(app).isEmpty }, "the kid's grid has titles")
        let shown = itemIDs(app)
        XCTAssertTrue(shown.isSubset(of: Self.kidFilms), "only U titles for Sam, got \(shown.sorted())")
        XCTAssertTrue(shown.isDisjoint(with: Self.adultOnlyFilms))
        XCTAssertFalse(element(app, "library.collection.9001").exists, "a collection with nothing for him is hidden")
        let card = element(app, "library.collection.9002")
        waitFor(card, timeout: 5)
        shot("wp10b-kid")
        XCTAssertTrue(focus(card, in: app))
        XCUIRemote.shared.press(.select)
        waitFor(element(app, "collection.root"), timeout: 10)
        XCTAssertTrue(waitUntil(8) { !self.itemIDs(app).isEmpty })
        let inCollection = itemIDs(app)
        XCTAssertTrue(inCollection.isSubset(of: Self.kidFilms), "collection titles for Sam: \(inCollection.sorted())")
        XCTAssertFalse(inCollection.contains("1011"), "the 15 title in Family nights is hidden")
    }
}
