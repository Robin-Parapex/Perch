import XCTest

/// WP-08/WP-09: artwork on Home with the fake household. `-PerchSlowArtwork` holds the full-size images for
/// 6 s (the 64 px stand-ins come at once), so cards are first seen as placeholders and then as loaded images.
/// No spinner may show at any point.
final class ArtworkUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsPlaceholdersThenArtwork() throws {
        let app = launchApp(.noPINs, extraArguments: ["-PerchSlowArtwork", "-PerchUITests"])
        try completeWizard(app, .noPINs)
        if element(app, "root.picker").exists { pickProfile(1001, app) }
        waitFor(element(app, "home.root"), timeout: 20)
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let placeholder = app.descendants(matching: .any)["artwork.placeholder"].firstMatch
        let loaded = app.descendants(matching: .any)["artwork.loaded"].firstMatch
        waitFor(placeholder, timeout: 10, "cards should first show placeholders")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner while artwork loads")
        shot("40-artwork-placeholders")

        XCTAssertTrue(loaded.waitForExistence(timeout: 10), "at least one artwork.loaded within 10 s")
        XCTAssertEqual(app.activityIndicators.count, 0, "no spinner once artwork is in")
        shot("41-artwork-loaded")
    }
}
