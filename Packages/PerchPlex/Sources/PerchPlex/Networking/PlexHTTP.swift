import Foundation
import PerchCore
import os

let plexLog = Logger(subsystem: "com.robrolabs.perch", category: "plex")

/// One HTTP round trip. Tests swap in a fake; the app uses `URLSessionTransport`.
public protocol PlexTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Ephemeral session, 15 s timeout, no cache, so nothing Plex sends is written to disk.
public struct URLSessionTransport: PlexTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum PlexError: Error, Equatable, Sendable {
    case notSignedIn
    case plexTVUnreachable
    case serverUnreachable
    case unauthorized
    case pinIncorrect
    case pinRequired
    case lockedOut(until: Date)
    case linkExpired
    case http(Int)
    case decoding
    case serverMismatch
    /// The signed-in account is not the Plex Home admin.
    case notHomeOwner
    /// A profile switch is already running.
    case switchInProgress
    /// The switch needs an accepted Admin PIN check that the caller did not supply.
    case adminVerificationRequired
    /// The Home users changed since the PIN screen was chosen: the switch needs this instead. Nothing was sent.
    case requirementChanged(SwitchRequirement)
    /// The profile may not do this (or has no settings). Nothing was sent.
    case notAllowed
}

/// Which side of the network a request was talking to, so a transport failure maps to the right case.
public enum PlexHost: Sendable {
    case plexTV
    case server
}

extension PlexError {
    /// Transport failures (offline, timeout, DNS, TLS, refused) are "unreachable", never a failed attempt.
    public static func transport(_ error: Error, host: PlexHost) -> PlexError {
        if let plex = error as? PlexError { return plex }
        if error is CancellationError { return .serverUnreachable }
        return host == .plexTV ? .plexTVUnreachable : .serverUnreachable
    }

    /// Maps a status to an error: 2xx is fine, 401/403 is `unauthorized`, anything else is `http`.
    public static func forStatus(_ status: Int) -> PlexError? {
        switch status {
        case 200..<300: nil
        case 401, 403: .unauthorized
        default: .http(status)
        }
    }
}

extension PlexTransport {
    /// Sends and maps every failure to a `PlexError`. Returns the body of a 2xx response.
    public func perform(_ request: URLRequest, host: PlexHost) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        // Path only: the query can carry a profile PIN, and tokens travel in headers.
        let path = request.url?.path ?? "?"
        do {
            (data, response) = try await send(request)
        } catch {
            plexLog.error("\(request.httpMethod ?? "GET", privacy: .public) \(path, privacy: .public) failed: \((error as? URLError)?.code.rawValue ?? -1, privacy: .public)")
            throw PlexError.transport(error, host: host)
        }
        if let failure = PlexError.forStatus(response.statusCode) {
            plexLog.error("\(request.httpMethod ?? "GET", privacy: .public) \(path, privacy: .public) returned \(response.statusCode, privacy: .public)")
            throw failure
        }
        return data
    }
}

/// JSON decoding shared by every model. plex.tv dates are ISO 8601, with or without fractions.
public enum PlexJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Bad date"))
        }
        return decoder
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch let error as DecodingError {
            // Coding path and reason only; DecodingError does not carry the values.
            plexLog.error("Decoding \(String(describing: T.self), privacy: .public) failed: \(decodingSummary(error), privacy: .public)")
            throw PlexError.decoding
        } catch {
            throw PlexError.decoding
        }
    }

    private static func decodingSummary(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context): return "missing \(key.stringValue) at \(path(context))"
        case .typeMismatch(let type, let context): return "expected \(type) at \(path(context))"
        case .valueNotFound(let type, let context): return "null \(type) at \(path(context))"
        case .dataCorrupted(let context): return "corrupt at \(path(context))"
        @unknown default: return "unknown"
        }
    }

    static func parseDate(_ text: String) -> Date? {
        let plain = Date.ISO8601FormatStyle()
        if let date = try? plain.parse(text) { return date }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? fractional.parse(text)
    }
}
