import Foundation
import PerchCore

/// Checks the owner's Plex Home PIN for the Admin PIN, using the switch endpoint. The token it
/// returns is discarded; nothing about the current profile changes.
public struct PlexOwnerPINVerifier: PlexPINVerifying {
    private let transport: any PlexTransport
    private let endpoints: PlexEndpoints
    private let secrets: any SecretStore
    private let settings: SettingsStore

    public init(
        transport: any PlexTransport, endpoints: PlexEndpoints, secrets: any SecretStore,
        settings: SettingsStore
    ) {
        self.transport = transport
        self.endpoints = endpoints
        self.secrets = secrets
        self.settings = settings
    }

    /// True on success, false when Plex refuses the PIN, throws `PlexPINError.unreachable` otherwise.
    public func verifyOwnerPIN(_ pin: String) async throws -> Bool {
        // The token is read now, so signing in later still works with a verifier built earlier.
        guard let token = try? secrets.string(for: .plexOwnerToken),
            let ownerID = await settings.document.household.ownerPlexUserID
        else { throw PlexPINError.unreachable }
        do {
            let request = endpoints.switchUser(id: ownerID.rawValue, pin: pin, ownerToken: token)
            _ = try await transport.perform(request, host: .plexTV)
            return true
        } catch PlexError.unauthorized {
            return false
        } catch {
            throw PlexPINError.unreachable
        }
    }
}
