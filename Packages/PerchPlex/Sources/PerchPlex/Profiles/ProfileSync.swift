import Foundation
import PerchCore

public struct ProfileSyncResult: Sendable, Equatable {
    public let document: SettingsDocument
    /// The owner's Home user id (falls back to the account id when Plex does not list the owner).
    public let ownerUserID: PlexUserID
    /// Whether the owner's Home user has a PIN; nil when the owner is not in the list.
    public let ownerHasPlexPIN: Bool?
}

/// Plex Home users -> the settings document. Pure; the caller saves the result.
public enum ProfileSync {
    /// The owner is the Plex Home admin, never just whichever account signed in.
    public static func ownerUser(in users: [PlexHomeUser]) -> PlexHomeUser? {
        users.first(where: \.admin)
    }

    public static func sync(
        homeUsers: [PlexHomeUser], ownerAccount account: PlexAccount, into document: SettingsDocument
    ) -> ProfileSyncResult {
        var doc = document
        let owner = ownerUser(in: homeUsers)
        let ownerID = PlexUserID(owner?.id ?? String(account.id))
        doc.household.ownerPlexUserID = ownerID

        for user in homeUsers {
            let id = PlexUserID(user.id)
            let isOwner = user.admin && id == ownerID
            // Plex is the source of truth for the restriction; roles and overrides stay as set.
            let restriction: PlexRestriction = isOwner ? .unrestricted : user.restriction
            if var existing = doc.profiles[id] {
                existing.plexRestriction = restriction
                existing.displayName = user.displayName
                // Never leave an override above what Plex now allows.
                if let override = existing.ceilingOverride { existing.setCeilingOverride(override) }
                doc.profiles[id] = existing
            } else {
                doc.profiles[id] = ProfileSettings.defaults(
                    plexUserID: id, displayName: user.displayName, isOwner: isOwner,
                    restriction: restriction)
            }
        }
        return ProfileSyncResult(document: doc, ownerUserID: ownerID, ownerHasPlexPIN: owner?.protected)
    }
}
