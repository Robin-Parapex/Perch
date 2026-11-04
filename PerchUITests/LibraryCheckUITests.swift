import XCTest

/// WP-06: the DEBUG Library check on the fake household. Counts and the marker row come from the
/// canned library answers in `FakeHouseholdTransport` (2 sections; Continue watching 2, Up next 1,
/// Recently added 3; an episode with an intro marker and final credits).
final class LibraryCheckUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLibraryCheckShowsHouseholdLibrary() throws {
        let app = launchApp(.noPINs)
        try completeWizard(app, .noPINs)
        // After setup the picker may show once; choose the owner, then end on home.
        if element(app, "root.picker").exists { pickProfile(1001, app) }
        waitFor(element(app, "home.profileName"), timeout: 20)
        tap("placeholder.libraryCheck", in: app)
        waitFor(element(app, "libraryCheck.title"))

        XCTAssertTrue(waitUntil(20) { self.element(app, "libraryCheck.count.sections").exists || self.element(app, "libraryCheck.error").exists })
        XCTAssertFalse(element(app, "libraryCheck.error").exists, "error: \(text(element(app, "libraryCheck.error")))")
        XCTAssertTrue(waitUntil(15) { self.text(self.element(app, "libraryCheck.count.sections")) == "2" })
        for (id, expected) in [("plex.continueWatching", "2"), ("plex.upNext", "1"), ("plex.recentlyAdded", "3")] {
            let counter = element(app, "libraryCheck.count.\(id)")
            XCTAssertTrue(waitUntil(15) { self.text(counter) == expected }, "\(id) count was '\(text(counter))', expected \(expected)")
        }

        let marker = element(app, "libraryCheck.marker.intro")
        waitFor(marker, timeout: 15)
        XCTAssertEqual(text(marker), "intro 0:05 to 0:15")
        XCTAssertTrue(text(element(app, "libraryCheck.marker.credits")).hasSuffix("final"))
        shot("30-library-check")
    }
}
