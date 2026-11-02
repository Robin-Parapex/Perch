import Foundation
import Testing

@testable import PerchCore

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Overlap {
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var runs = 0
    func begin() { inFlight += 1; runs += 1; maxInFlight = max(maxInFlight, inFlight) }
    func end() { inFlight -= 1 }
}

private func waitUntil(_ condition: @escaping () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

struct PollingTests {
    private let stepped = PollingPolicy(
        steps: [
            .init(interval: .seconds(30), duration: .seconds(600)),
            .init(interval: .seconds(120), duration: .seconds(3000)),
        ],
        finalInterval: .seconds(300))

    @Test func steppedIntervals() {
        #expect(stepped.interval(afterElapsed: .zero) == .seconds(30))
        #expect(stepped.interval(afterElapsed: .seconds(599)) == .seconds(30))
        #expect(stepped.interval(afterElapsed: .seconds(600)) == .seconds(120))
        #expect(stepped.interval(afterElapsed: .seconds(3599)) == .seconds(120))
        #expect(stepped.interval(afterElapsed: .seconds(3600)) == .seconds(300))
        #expect(stepped.interval(afterElapsed: .seconds(3 * 3600)) == .seconds(300))
    }

    @Test func fixedPolicy() {
        let p = PollingPolicy.fixed(.seconds(45))
        #expect(p.whileActiveOnly)
        #expect(p.interval(afterElapsed: .zero) == .seconds(45))
        #expect(p.interval(afterElapsed: .seconds(100_000)) == .seconds(45))
        #expect(!PollingPolicy.fixed(.seconds(1), whileActiveOnly: false).whileActiveOnly)
    }

    @Test func runsImmediatelyAndStops() async {
        let counter = Counter()
        let poller = Poller(id: "p", policy: .fixed(.milliseconds(20))) { await counter.increment() }
        await poller.start()
        #expect(await poller.isRunning)
        #expect(await waitUntil { await counter.value >= 3 })
        await poller.stop()
        #expect(await !poller.isRunning)
        try? await Task.sleep(for: .milliseconds(60))
        let settled = await counter.value
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await counter.value == settled)
    }

    @Test func restartScheduleRunsJobAgain() async {
        let counter = Counter()
        // Long interval: only an immediate run happens per start.
        let poller = Poller(id: "p", policy: .fixed(.seconds(60))) { await counter.increment() }
        await poller.start()
        #expect(await waitUntil { await counter.value == 1 })
        await poller.start()  // no-op while running
        await poller.restartSchedule()
        #expect(await waitUntil { await counter.value == 2 })
        #expect(await poller.isRunning)
        await poller.stop()
    }

    @Test func coordinatorHonoursWhileActiveOnly() async {
        let coordinator = PollerCoordinator()
        let foreground = Poller(id: "fg", policy: .fixed(.milliseconds(20))) {}
        let background = Poller(
            id: "bg", policy: .fixed(.milliseconds(20), whileActiveOnly: false)
        ) {}
        await coordinator.register(foreground)
        await coordinator.register(background)
        #expect(await !foreground.isRunning)

        await coordinator.setAppActive(true)
        #expect(await coordinator.isAppActive)
        #expect(await foreground.isRunning)
        #expect(await background.isRunning)

        await coordinator.setAppActive(false)
        #expect(await !foreground.isRunning)
        #expect(await background.isRunning)

        await coordinator.setAppActive(true)
        #expect(await foreground.isRunning)

        await foreground.stop()
        await background.stop()
    }

    private func slowPoller(_ overlap: Overlap, whileActiveOnly: Bool = true) -> Poller {
        Poller(id: "slow", policy: .fixed(.seconds(60), whileActiveOnly: whileActiveOnly)) {
            await overlap.begin()
            // Unstructured, so cancelling the loop does not cut the job short.
            await Task { try? await Task.sleep(for: .milliseconds(100)) }.value
            await overlap.end()
        }
    }

    @Test func restartMidRunNeverOverlaps() async {
        let overlap = Overlap()
        let poller = slowPoller(overlap)
        await poller.start()
        #expect(await waitUntil { await overlap.inFlight == 1 })
        await poller.restartSchedule()
        await poller.stop()
        await poller.start()
        #expect(await waitUntil { await overlap.runs >= 2 })
        try? await Task.sleep(for: .milliseconds(150))
        await poller.stop()
        #expect(await waitUntil { await overlap.inFlight == 0 })
        #expect(await overlap.maxInFlight == 1)
    }

    @Test func registerWhileActiveThenInactiveLeavesStopped() async {
        let coordinator = PollerCoordinator()
        let poller = Poller(id: "fg", policy: .fixed(.milliseconds(20))) {}
        await coordinator.setAppActive(true)
        async let registered: Void = coordinator.register(poller)
        async let deactivated: Void = coordinator.setAppActive(false)
        _ = await (registered, deactivated)
        #expect(await !coordinator.isAppActive)
        #expect(await !poller.isRunning)
    }

    @Test func unregisterDuringActivationLeavesPollerStopped() async {
        for i in 0..<20 {
            let coordinator = PollerCoordinator()
            let a = Poller(id: "a\(i)", policy: .fixed(.milliseconds(20))) {}
            await coordinator.register(a)
            async let activated: Void = coordinator.setAppActive(true)
            async let removed: Void = coordinator.unregister(id: a.id)
            _ = await (activated, removed)
            #expect(await !a.isRunning)
        }
    }

    @Test func rapidActiveFlipsEndConsistent() async {
        let coordinator = PollerCoordinator()
        let pollers = (0..<5).map {
            Poller(id: "p\($0)", policy: .fixed(.milliseconds(20))) {}
        }
        for p in pollers { await coordinator.register(p) }
        async let a: Void = coordinator.setAppActive(true)
        async let b: Void = coordinator.setAppActive(false)
        async let c: Void = coordinator.setAppActive(true)
        async let d: Void = coordinator.setAppActive(false)
        _ = await (a, b, c, d)
        // Call order at the actor is not fixed; whichever ran last must be reflected everywhere.
        let active = await coordinator.isAppActive
        for p in pollers { #expect(await p.isRunning == active) }
        for p in pollers { await p.stop() }
    }
}
