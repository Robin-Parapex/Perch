import Foundation

/// A stepped polling schedule: each step applies for `duration`, then the next; after the last
/// step `finalInterval` applies. Polling replaces webhooks because the app has no server.
public struct PollingPolicy: Sendable, Equatable {
    public struct Step: Sendable, Equatable {
        public var interval: Duration
        public var duration: Duration

        public init(interval: Duration, duration: Duration) {
            self.interval = interval
            self.duration = duration
        }
    }

    public var steps: [Step]
    public var finalInterval: Duration
    /// Stop while the app is in the background (foreground-only polling).
    public var whileActiveOnly: Bool

    public init(steps: [Step], finalInterval: Duration, whileActiveOnly: Bool = true) {
        self.steps = steps
        self.finalInterval = finalInterval
        self.whileActiveOnly = whileActiveOnly
    }

    public static func fixed(_ interval: Duration, whileActiveOnly: Bool = true) -> PollingPolicy {
        PollingPolicy(steps: [], finalInterval: interval, whileActiveOnly: whileActiveOnly)
    }

    /// The interval to wait when `elapsed` has passed since the schedule began.
    public func interval(afterElapsed elapsed: Duration) -> Duration {
        var windowEnd = Duration.zero
        for step in steps {
            windowEnd += step.duration
            if elapsed < windowEnd { return step.interval }
        }
        return finalInterval
    }
}

/// Runs one job on a policy's schedule. Runs never overlap.
public actor Poller {
    public nonisolated let id: String
    public nonisolated let policy: PollingPolicy
    private let clock: any Clock<Duration>
    private let job: @Sendable () async -> Void
    private var task: Task<Void, Never>?
    /// A cancelled loop that may still be finishing its last job.
    private var finishing: Task<Void, Never>?

    public init(
        id: String,
        policy: PollingPolicy,
        clock: any Clock<Duration> = ContinuousClock(),
        job: @escaping @Sendable () async -> Void
    ) {
        self.id = id
        self.policy = policy
        self.clock = clock
        self.job = job
    }

    public var isRunning: Bool { task != nil }

    /// No-op if already running. Runs the job immediately, then on the schedule.
    public func start() {
        guard task == nil else { return }
        launch(after: nil)
    }

    public func stop() {
        task?.cancel()
        if let task { finishing = task }
        task = nil
    }

    /// Begin the stepped schedule again (used when a new request is made).
    public func restartSchedule() {
        task?.cancel()
        launch(after: task)
    }

    private func launch(after old: Task<Void, Never>?) {
        let policy = policy
        let clock = clock
        let job = job
        let previous = old ?? finishing
        task = Task {
            // Runs never overlap: wait for a cancelled loop's in-flight job to finish.
            await previous?.value
            var elapsed = Duration.zero
            while !Task.isCancelled {
                await job()
                let interval = policy.interval(afterElapsed: elapsed)
                do { try await clock.sleep(for: interval) } catch { return }
                elapsed += interval
            }
        }
        finishing = nil
    }
}

/// Starts and stops registered pollers as the app becomes active or inactive.
public actor PollerCoordinator {
    private var pollers: [String: Poller] = [:]
    public private(set) var isAppActive = false
    private var generation = 0

    public init() {}

    public func register(_ poller: Poller) async {
        pollers[poller.id] = poller
        if isAppActive {
            await poller.start()
            // setAppActive(false) may have run during the await; the last call wins.
            if !isAppActive, poller.policy.whileActiveOnly { await poller.stop() }
        }
    }

    public func unregister(id: String) async {
        guard let poller = pollers.removeValue(forKey: id) else { return }
        await poller.stop()
    }

    /// The last call wins: a newer call makes an older one stop touching further pollers.
    public func setAppActive(_ active: Bool) async {
        generation += 1
        let mine = generation
        isAppActive = active
        for poller in Array(pollers.values) {
            guard generation == mine, isAppActive == active else { return }
            // Skip pollers unregistered while this loop was suspended.
            guard pollers[poller.id] === poller else { continue }
            if active {
                await poller.start()
                // Unregistered during the start: unregister's stop may already have run.
                if pollers[poller.id] !== poller { await poller.stop() }
            } else if poller.policy.whileActiveOnly {
                await poller.stop()
            }
        }
    }
}
