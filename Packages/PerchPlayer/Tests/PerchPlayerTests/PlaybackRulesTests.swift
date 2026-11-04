import PerchCore
import Testing

@testable import PerchPlayer

@Suite struct SkipRulesTests {
    let intro = MediaMarker(kind: .intro, startMs: 10_000, endMs: 40_000)

    @Test func introWindowEdges() {
        var rules = SkipRules(markers: [intro], durationMs: 1_000_000)
        #expect(rules.offer(atMs: 9_999, isSeeking: false) == nil)
        #expect(rules.offer(atMs: 10_000, isSeeking: false)?.kind == .intro)
        #expect(rules.offer(atMs: 39_999, isSeeking: false) != nil)
        #expect(rules.offer(atMs: 40_000, isSeeking: false) == nil)
    }

    @Test func padAndClamp() {
        var rules = SkipRules(markers: [intro], durationMs: 1_000_000)
        #expect(rules.offer(atMs: 10_000, isSeeking: false)?.targetMs == 40_500)
        var short = SkipRules(markers: [intro], durationMs: 40_800)
        #expect(short.offer(atMs: 10_000, isSeeking: false)?.targetMs == 39_800)
        var unknown = SkipRules(markers: [intro], durationMs: nil)
        #expect(unknown.offer(atMs: 10_000, isSeeking: false)?.targetMs == 40_500)
    }

    @Test func noOfferWhileSeeking() {
        var rules = SkipRules(markers: [intro], durationMs: 1_000_000)
        #expect(rules.offer(atMs: 20_000, isSeeking: true) == nil)
    }

    @Test func autoSkipOnlyOncePerMarker() {
        var rules = SkipRules(markers: [intro], durationMs: 1_000_000, policy: PlaybackPolicy(autoSkipIntro: true))
        let first = rules.offer(atMs: 20_000, isSeeking: false)
        #expect(first?.autoSkipAfterSeconds == 5)
        rules.markSpent(first!.markerID)
        let again = rules.offer(atMs: 20_000, isSeeking: false)
        #expect(again != nil)
        #expect(again?.autoSkipAfterSeconds == nil)
    }

    @Test func noAutoSkipWhenPolicyOff() {
        var rules = SkipRules(markers: [intro], durationMs: 1_000_000)
        #expect(rules.offer(atMs: 20_000, isSeeking: false)?.autoSkipAfterSeconds == nil)
    }

    @Test func finalCreditsGivesNoOffer() {
        let credits = MediaMarker(kind: .credits, startMs: 900_000, endMs: 1_000_000, isFinal: true)
        var rules = SkipRules(markers: [credits], durationMs: 1_000_000)
        #expect(rules.offer(atMs: 950_000, isSeeking: false) == nil)
    }

    @Test func nonFinalCreditsGivesOffer() {
        let credits = MediaMarker(kind: .credits, startMs: 500_000, endMs: 560_000, isFinal: false)
        var rules = SkipRules(markers: [credits], durationMs: 1_000_000, policy: PlaybackPolicy(autoSkipCredits: true))
        let offer = rules.offer(atMs: 500_000, isSeeking: false)
        #expect(offer?.kind == .credits)
        #expect(offer?.targetMs == 560_500)
        #expect(offer?.autoSkipAfterSeconds == 5)
    }
}

@Suite struct UpNextRulesTests {
    let finalCredits = MediaMarker(kind: .credits, startMs: 3_000_000, endMs: 3_600_000, isFinal: true)

    private func rules(
        markers: [MediaMarker] = [], duration: Int? = 3_600_000, hasNext: Bool = true,
        policy: PlaybackPolicy = .household, chain: Int = 0
    ) -> UpNextRules {
        UpNextRules(markers: markers, durationMs: duration, hasNext: hasNext, policy: policy, autoChainCount: chain)
    }

    @Test func estimatedCreditsStart() {
        #expect(rules(duration: 3_600_000).creditsStartMs == 3_480_000)
        #expect(rules(duration: 3_600_000).isEstimated)
        #expect(rules(duration: 1_320_000).creditsStartMs == 1_320_000 - 52_800)
        #expect(rules(duration: 600_000).creditsStartMs == 555_000)
        #expect(rules(duration: 299_999).creditsStartMs == nil)
        #expect(rules(duration: nil).creditsStartMs == nil)
    }

    @Test func markerStartIsUsedAndNotEstimated() {
        let r = rules(markers: [finalCredits])
        #expect(r.creditsStartMs == 3_000_000)
        #expect(!r.isEstimated)
    }

    @Test func idleBeforeStartOrWithoutNext() {
        var r = rules(markers: [finalCredits])
        #expect(r.phase(atMs: 2_999_999) == .idle)
        var none = rules(markers: [finalCredits], hasNext: false)
        #expect(none.phase(atMs: 3_100_000) == .idle)
    }

    @Test func timedWhenRealMarker() {
        var r = rules(markers: [finalCredits])
        #expect(r.phase(atMs: 3_000_000) == .proposed(.timed(seconds: 10)))
    }

    @Test func manualWhenEstimated() {
        var r = rules()
        #expect(r.phase(atMs: 3_500_000) == .proposed(.manual))
    }

    @Test func manualWhenAutoplayOff() {
        var r = rules(markers: [finalCredits], policy: PlaybackPolicy(autoplayNext: false))
        #expect(r.phase(atMs: 3_100_000) == .proposed(.manual))
    }

    @Test func manualWhenChainAtLimit() {
        var r = rules(markers: [finalCredits], chain: 3)
        #expect(r.phase(atMs: 3_100_000) == .proposed(.manual))
        var below = rules(markers: [finalCredits], chain: 2)
        #expect(below.phase(atMs: 3_100_000) == .proposed(.timed(seconds: 10)))
    }

    @Test func dismissedThenSeekBackIsManual() {
        var r = rules(markers: [finalCredits])
        #expect(r.phase(atMs: 3_100_000) == .proposed(.timed(seconds: 10)))
        r.dismiss()
        #expect(r.phase(atMs: 3_200_000) == .dismissed)
        #expect(r.phase(atMs: 1_000_000) == .idle)
        #expect(r.phase(atMs: 3_100_000) == .proposed(.manual))
    }

    @Test func endActionCases() {
        #expect(rules(hasNext: false).endAction() == .stop)
        #expect(rules(policy: PlaybackPolicy(autoplayNext: false)).endAction() == .stop)
        #expect(rules(chain: 3).endAction() == .stillWatching)
        #expect(rules(chain: 5).endAction() == .stillWatching)
        #expect(rules(chain: 2).endAction() == .advance)
        #expect(rules(chain: 0).endAction() == .advance)
    }

    @Test func endActionAfterDismissIsStop() {
        var r = rules(markers: [finalCredits])
        _ = r.phase(atMs: 3_100_000)
        r.dismiss()
        #expect(r.endAction() == .stop)
    }
}

@Suite struct AutoChainCounterTests {
    @Test func resetsOnInput() {
        var counter = AutoChainCounter()
        counter.automaticAdvance()
        counter.automaticAdvance()
        #expect(counter.count == 2)
        counter.userInput()
        #expect(counter.count == 0)
    }

    @Test func policyDefaults() {
        let p = PlaybackPolicy.household
        #expect(!p.autoSkipIntro && !p.autoSkipCredits && p.autoplayNext)
        #expect(p.upNextCountdownSeconds == 10 && p.stillWatchingAfter == 3)
        #expect(p.skipPadMs == 500 && p.autoSkipCountdownSeconds == 5)
    }
}
