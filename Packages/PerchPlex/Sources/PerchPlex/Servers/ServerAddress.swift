import Foundation

public enum ServerAddressError: Error, Equatable, Sendable {
    case empty
    case invalidHost
    case invalidPort
    case unsupportedScheme
}

/// Turns what a person types ("192.168.1.5", "https://plex.home:443", "::1") into a base URL.
/// Defaults: scheme http, port 32400. IPv6 is bracketed in the result.
public enum ServerAddress {
    public static func parse(_ text: String) throws -> URL {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { throw ServerAddressError.empty }

        var scheme = "http"
        if let range = rest.range(of: "://") {
            let given = rest[..<range.lowerBound].lowercased()
            guard given == "http" || given == "https" else { throw ServerAddressError.unsupportedScheme }
            scheme = given
            rest = String(rest[range.upperBound...])
        }
        while rest.hasSuffix("/") { rest.removeLast() }
        guard !rest.isEmpty,
            !rest.contains(where: { $0.isWhitespace || "/?#@".contains($0) })
        else { throw ServerAddressError.invalidHost }

        let host: String
        var portText: String?
        if rest.hasPrefix("[") {
            guard let close = rest.firstIndex(of: "]") else { throw ServerAddressError.invalidHost }
            let inner = String(rest[rest.index(after: rest.startIndex)..<close])
            guard isIPv6(inner) else { throw ServerAddressError.invalidHost }
            host = "[\(inner)]"
            let after = rest[rest.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else { throw ServerAddressError.invalidHost }
                portText = String(after.dropFirst())
            }
        } else if rest.filter({ $0 == ":" }).count >= 2 {
            guard isIPv6(rest) else { throw ServerAddressError.invalidHost }
            host = "[\(rest)]"
        } else {
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0])
            guard isHostname(name) else { throw ServerAddressError.invalidHost }
            host = name
            if parts.count == 2 { portText = String(parts[1]) }
        }

        var port = 32400
        if let portText {
            guard let value = Int(portText), (1...65535).contains(value) else {
                throw ServerAddressError.invalidPort
            }
            port = value
        }
        guard let url = URL(string: "\(scheme)://\(host):\(port)") else {
            throw ServerAddressError.invalidHost
        }
        return url
    }

    private static func isHostname(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("."), !name.hasPrefix("-") else { return false }
        return name.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private static func isIPv6(_ text: String) -> Bool {
        guard text.contains(":"), text.count >= 2 else { return false }
        let core = text.split(separator: "%", maxSplits: 1)[0]
        return core.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
            && core.filter({ $0 == ":" }).count >= 2
    }
}
