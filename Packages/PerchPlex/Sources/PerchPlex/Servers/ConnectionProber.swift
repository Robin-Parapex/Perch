import Foundation

/// Sleeps for a duration. Injected so tests run fast. It must really wait (a no-op sleep makes every
/// timeout and grace period fire at once).
public typealias PlexSleep = @Sendable (Duration) async throws -> Void

public struct ProbeResult: Sendable, Equatable {
    public let url: URL
    public let tier: PlexConnectionTier
    public let identity: PlexServerIdentity
}

extension PlexConnection {
    /// A connection for an address that did not come from plex.tv (typed in, or remembered).
    /// Private-range and `.local` hosts count as local so they get the short timeout.
    public static func manual(url: URL) -> PlexConnection {
        let host = url.host(percentEncoded: false) ?? ""
        let port = url.port ?? 32400
        return PlexConnection(
            protocol: url.scheme ?? "http", address: host, port: port, uri: url.absoluteString,
            local: isPrivateHost(host), relay: false, isIPv6: host.contains(":"))
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") || lower.hasSuffix(".lan") { return true }
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower.hasPrefix("fe80") { return lower.contains(":") }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

/// Picks the best working address for a server. Idea from Dusk ServerProbe (MIT): probe `/identity`
/// on every connection at once; local beats remote beats relay.
public struct ConnectionProber: Sendable {
    public struct Timing: Sendable {
        public var localTimeout: Duration
        public var remoteTimeout: Duration
        /// How long to keep waiting for a better tier once any tier has answered.
        public var grace: Duration
        public var sleep: PlexSleep

        public init(
            localTimeout: Duration = .seconds(5), remoteTimeout: Duration = .seconds(8),
            grace: Duration = .milliseconds(1500),
            sleep: @escaping PlexSleep = { try await Task.sleep(for: $0) }
        ) {
            self.localTimeout = localTimeout
            self.remoteTimeout = remoteTimeout
            self.grace = grace
            self.sleep = sleep
        }

        public static let standard = Timing()
    }

    private enum Event: Sendable {
        case answered(Int, PlexServerIdentity?)
        case graceElapsed
    }

    private enum Race: Sendable {
        case answer(PlexServerIdentity?)
        case timedOut
    }

    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let timing: Timing

    public init(transport: any PlexTransport, endpoints: PlexEndpoints, timing: Timing = .standard) {
        self.transport = transport
        self.endpoints = endpoints
        self.timing = timing
    }

    /// - Parameters:
    ///   - lastGood: tried first on its own; wins if it answers.
    ///   - expectedMachineID: when set, an address that answers as a different server does not count
    ///     (`serverMismatch` if nothing else answers).
    public func probe(
        connections: [PlexConnection], lastGood: URL? = nil, expectedMachineID: String? = nil
    ) async throws -> ProbeResult {
        var sawMismatch = false

        var ordered: [(url: URL, tier: PlexConnectionTier)] = []
        var seen = Set<String>()
        for connection in connections.enumerated().sorted(by: {
            ($0.element.tier, $0.offset) < ($1.element.tier, $1.offset)
        }).map(\.element) {
            guard let url = connection.url, seen.insert(url.absoluteString).inserted else { continue }
            ordered.append((url, connection.tier))
        }

        if let lastGood {
            let tier = ordered.first { $0.url == lastGood }?.tier ?? PlexConnection.manual(url: lastGood).tier
            if let identity = await identity(at: lastGood, tier: tier) {
                if matches(identity, expectedMachineID) {
                    return ProbeResult(url: lastGood, tier: tier, identity: identity)
                }
                sawMismatch = true
            }
            ordered.removeAll { $0.url == lastGood }
        }
        guard !ordered.isEmpty else { throw sawMismatch ? PlexError.serverMismatch : PlexError.serverUnreachable }

        let candidates = ordered
        let best = await withTaskGroup(of: Event.self) { group -> (ProbeResult?, Bool) in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { .answered(index, await self.identity(at: candidate.url, tier: candidate.tier)) }
            }
            var best: ProbeResult?
            var mismatch = false
            var graceStarted = false
            loop: for await event in group {
                switch event {
                case .answered(let index, let identity?):
                    guard matches(identity, expectedMachineID) else {
                        mismatch = true
                        continue loop
                    }
                    let candidate = candidates[index]
                    if best == nil || candidate.tier < best!.tier {
                        best = ProbeResult(url: candidate.url, tier: candidate.tier, identity: identity)
                    }
                    if candidate.tier == .local { break loop }
                    if !graceStarted {
                        graceStarted = true
                        group.addTask {
                            try? await self.timing.sleep(self.timing.grace)
                            return .graceElapsed
                        }
                    }
                case .answered(_, nil):
                    continue loop
                case .graceElapsed:
                    break loop
                }
            }
            group.cancelAll()
            return (best, mismatch)
        }
        sawMismatch = sawMismatch || best.1
        if let result = best.0 { return result }
        throw sawMismatch ? PlexError.serverMismatch : PlexError.serverUnreachable
    }

    private func matches(_ identity: PlexServerIdentity, _ expected: String?) -> Bool {
        expected == nil || identity.machineIdentifier == expected
    }

    private func identity(at url: URL, tier: PlexConnectionTier) async -> PlexServerIdentity? {
        let timeout = tier == .local ? timing.localTimeout : timing.remoteTimeout
        let transport = transport
        let request = endpoints.serverIdentity(base: url)
        let sleep = timing.sleep
        return await withTaskGroup(of: Race.self) { group in
            group.addTask {
                do {
                    let data = try await transport.perform(request, host: .server)
                    return .answer(try? PlexServerIdentity.decode(from: data))
                } catch {
                    return .answer(nil)
                }
            }
            group.addTask {
                try? await sleep(timeout)
                return .timedOut
            }
            let first = await group.next()
            group.cancelAll()
            if case .answer(let identity)? = first { return identity }
            return nil
        }
    }
}
