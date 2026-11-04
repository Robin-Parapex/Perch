import Foundation
import PerchCore
import Testing
import UIKit

@testable import PerchPlayer

private struct ResolveFailure: Error {}

/// WP-07 review findings: failures while advancing, the up next dismissal, and the finish handler chain.
@MainActor
@Suite struct PlaybackSessionReviewTests {
    private func acceptAtCredits(_ h: Harness) async {
        await h.tick(46_000)
        await until { h.engine.onAccept != nil }
        h.engine.onAccept?(.user)
    }

    @Test func failureWhileAdvancingIsLoggedAgainstTheNextItem() async {
        let h = Harness()
        h.resolveError = ResolveFailure()
        await h.start()
        await acceptAtCredits(h)
        await until { h.session.overlayRequest != nil }
        #expect(h.session.overlayRequest == .playbackFailed(message: Harness.failureCopy))
        await h.session.settle()
        let log = await h.log.items
        let failure = log.last
        #expect(failure?.outcome == .failure)
        #expect(failure?.ratingKey == "next" && failure?.title == "Next")
        #expect(failure?.method == nil)
        // The finished item logged its stop once and nothing else after it.
        #expect(log.filter { $0.ratingKey == "100" }.map(\.outcome) == [.start, .stop])
        #expect(await h.reporter.stops.count == 1)
        #expect(h.engine.loads.map(\.ratingKey) == ["100"])
    }

    @Test func retryAfterAFailedAdvanceAdvancesAgain() async {
        let h = Harness()
        h.resolveError = ResolveFailure()
        await h.start()
        await acceptAtCredits(h)
        await until { h.session.overlayRequest != nil }
        // Ticks from the finished item under the overlay bring no proposal back.
        let shows = h.engine.upNextShows
        h.engine.send(.positionTick(47_000))
        try? await Task.sleep(for: .milliseconds(20))
        #expect(h.engine.upNextShows == shows && h.engine.upNext == nil)
        h.resolveError = nil
        h.session.retry()
        await until { h.session.itemsStarted == 2 && h.session.phase == .playing }
        #expect(h.resolveCalls == 2)
        #expect(h.engine.loads.map(\.ratingKey) == ["100", "next"])
        #expect(h.session.source.ratingKey == "next")
        await h.session.settle()
        // No second stop for the finished item, and no reload of it.
        #expect(await h.reporter.stops.count == 1)
    }

    @Test func refusedNextItemEndsTheSession() async {
        let h = Harness()
        h.resolveError = PlaybackNotAllowed()
        await h.start()
        await acceptAtCredits(h)
        await until { h.session.phase == .finished }
        #expect(h.session.phase == .finished)
        #expect(h.session.overlayRequest == nil)
        #expect(h.finished == 1)
        #expect(h.engine.chromeHiddenCalls.isEmpty)
        // The phase turns finished before exit drains the queue: wait for the drain (a no-op once it ended).
        await h.session.settle()
        let log = await h.log.items
        #expect(log.contains { $0.ratingKey == "next" && $0.outcome == .failure })
        #expect(await h.reporter.stops.count == 1)
    }

    @Test func dismissedProposalStaysDownAcrossInputAndEndStops() async {
        let h = Harness()
        await h.start()
        await h.tick(46_000)
        #expect(h.engine.upNext != nil)
        h.engine.userDismissUpNext()
        h.engine.send(.userInput)
        await h.tick(50_000)
        #expect(h.engine.upNext == nil && h.session.upNextShown == nil)
        h.engine.send(.ended)
        await until { h.session.phase == .finished }
        #expect(h.finished == 1)
        #expect(h.engine.loads.count == 1)
    }

    @Test func seekBackAfterDismissClearsItAndInputDoesNotReapplyIt() async {
        let h = Harness()
        await h.start()
        await h.tick(46_000)
        h.engine.userDismissUpNext()
        // Back before the credits: the dismissal is gone. A button press (chain rebuild) must not bring it back.
        await h.tick(30_000)
        h.engine.send(.userInput)
        await h.tick(46_000)
        #expect(h.engine.upNext?.ratingKey == "next")
        // Dismissed once: never timed again for this item.
        #expect(h.engine.upNextMode == .manual)
        h.engine.send(.userInput)
        await h.tick(50_000)
        #expect(h.engine.upNext != nil)
        h.engine.send(.ended)
        await until { h.session.itemsStarted == 2 && h.session.phase == .playing }
        #expect(h.engine.loads.map(\.ratingKey) == ["100", "next"])
    }

    @Test func containerChainsToTheOwnersFinishHandler() async {
        let h = Harness()
        let container = PlayerContainerViewController(session: h.session)
        var exits = 0
        container.onExit = { exits += 1 }
        container.loadViewIfNeeded()
        await h.session.exit()
        #expect(h.finished == 1)
        #expect(exits == 1)
    }
}
