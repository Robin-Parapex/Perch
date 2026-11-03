import Foundation
import PerchCore

public enum LinkState: Sendable, Equatable {
    case code(String, expiresAt: Date)
    case linked(token: String)
    case failed(PlexError)
}

/// The plex.tv/link short-code flow: create a pin, show its code, poll until it carries a token.
/// A fresh code is issued automatically when the pin expires. Stops when the consuming task ends.
public struct PlexLinkFlow: Sendable {
    /// A pin lives about 15 minutes when plex.tv does not say.
    private static let fallbackLifetime: TimeInterval = 900
    /// Poll failures tolerated in a row before giving up (a TV on Wi-Fi drops a request now and then).
    private static let maxPollFailures = 3

    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let pollInterval: Duration
    private let sleep: PlexSleep
    private let now: NowProvider

    public init(
        transport: any PlexTransport, endpoints: PlexEndpoints,
        pollInterval: Duration = .seconds(2),
        sleep: @escaping PlexSleep = { try await Task.sleep(for: $0) },
        now: @escaping NowProvider = { Date() }
    ) {
        self.transport = transport
        self.endpoints = endpoints
        self.pollInterval = pollInterval
        self.sleep = sleep
        self.now = now
    }

    public func start() -> AsyncStream<LinkState> {
        let (stream, continuation) = AsyncStream<LinkState>.makeStream()
        let task = Task { await run(continuation) }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(_ out: AsyncStream<LinkState>.Continuation) async {
        defer { out.finish() }
        while !Task.isCancelled {
            let pin: PlexPin
            do {
                let data = try await transport.perform(endpoints.createPin(), host: .plexTV)
                pin = try PlexJSON.decode(PlexPin.self, from: data)
            } catch {
                if Task.isCancelled { return }
                out.yield(.failed(PlexError.transport(error, host: .plexTV)))
                return
            }
            let expiresAt = pin.expiresAt ?? now().addingTimeInterval(Self.fallbackLifetime)
            out.yield(.code(pin.code, expiresAt: expiresAt))

            var failures = 0
            polling: while !Task.isCancelled {
                do { try await sleep(pollInterval) } catch { return }
                if now() >= expiresAt { break polling }
                do {
                    let data = try await transport.perform(endpoints.checkPin(id: pin.id), host: .plexTV)
                    failures = 0
                    let checked = try PlexJSON.decode(PlexPin.self, from: data)
                    if let token = checked.authToken, !token.isEmpty {
                        out.yield(.linked(token: token))
                        return
                    }
                    if let end = checked.expiresAt, now() >= end { break polling }
                } catch PlexError.http(404) {
                    break polling  // plex.tv forgot the pin: expired
                } catch {
                    if Task.isCancelled { return }
                    failures += 1
                    if failures >= Self.maxPollFailures {
                        out.yield(.failed(PlexError.transport(error, host: .plexTV)))
                        return
                    }
                }
            }
        }
    }
}
