#if DEBUG
import Foundation
import PerchPlex

/// DEBUG-only demo switches (WP-04 decision 13). `-PerchFakePlexTVDown` fails plex.tv calls and
/// `-PerchFakeServerDown` fails every other host, both as "not connected to the internet".
struct FaultInjectingTransport: PlexTransport {
    let base: any PlexTransport
    let plexTVDown: Bool
    let serverDown: Bool

    static func wrapping(_ base: any PlexTransport, arguments: [String] = ProcessInfo.processInfo.arguments)
        -> any PlexTransport
    {
        let plexTVDown = arguments.contains("-PerchFakePlexTVDown")
        let serverDown = arguments.contains("-PerchFakeServerDown")
        guard plexTVDown || serverDown else { return base }
        return FaultInjectingTransport(base: base, plexTVDown: plexTVDown, serverDown: serverDown)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host(percentEncoded: false)?.lowercased() ?? ""
        let isPlexTV = host == "plex.tv" || host.hasSuffix(".plex.tv")
        if (isPlexTV && plexTVDown) || (!isPlexTV && serverDown) {
            throw URLError(.notConnectedToInternet)
        }
        return try await base.send(request)
    }
}
#endif
