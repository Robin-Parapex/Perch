import XCTest

/// WP-08: artwork on the DEBUG Library check with the fake household. `-PerchSlowArtwork` holds the full-size
/// images for 6 s (the 64 px stand-ins come at once), so the cards are first seen as placeholders and then
/// as loaded images. `libraryCheck.artwork.status` reads "Artwork placeholder=<n> loaded=<n>" for the
/// visible cards. No spinner may show at any point.
final class ArtworkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func counts(_ app: XCUIApplication) -> (placeholder: Int, loaded: Int) {
        let words = text(element(app, "libraryCheck.artwork.status")).split(separator: " ")
        func number(_ prefix: String) -> Int {
            words.first { $0.hasPrefix(prefix) }.flatMap { Int($0.dropFirst(prefix.count)) } ?? -1
        }
        return (number("placeholder="), number("loaded="))
    }

    @MainActor
    func testLibraryCheckShowsPlaceholdersThenArtwork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PerchFakeHousehold", Household.noPINs.rawValue, "-PerchResetSetup", "-PerchSlowArtwork"]
        app.launch()
        try completeWizard(app, .noPINs)
        if element(app, "root.picker").exists { pickProfile(1001, app) }
        waitFor(element(app, "home.profileName"), timeout: 20)
        tap("placeholder.libraryCheck", in: app)
        waitFor(element(app, "libraryCheck.title"))
        waitFor(element(app, "libraryCheck.artwork.status"))

        // First the stand-ins: cards on screen, none loaded yet.
        XCTAssertTrue(
            waitUntil(15) { let c = self.counts(app); return c.placeholder > 0 && c.loaded == 0 },
            "cards should first show placeholders, status '\(text(element(app, "libraryCheck.artwork.status")))'")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner while artwork loads")
        shot("40-artwork-placeholders")

        // Then the images: every visible card loaded.
        XCTAssertTrue(
            waitUntil(15) { let c = self.counts(app); return c.loaded > 0 && c.placeholder == 0 },
            "cards should load, status '\(text(element(app, "libraryCheck.artwork.status")))'")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner once artwork is in")
        XCTAssertTrue(element(app, "artwork.loaded").exists, "a card carries the artwork.loaded identifier")
        shot("41-artwork-loaded")
    }
}
