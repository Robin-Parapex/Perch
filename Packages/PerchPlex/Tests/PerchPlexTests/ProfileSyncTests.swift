import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private func homeUsers() throws -> [PlexHomeUser] {
    try PlexHomeUser.decodeList(from: Fixture.data("home_users"))
}

private func account() throws -> PlexAccount {
    try PlexJSON.decode(PlexAccount.self, from: Fixture.data("user"))
}

@Suite("Profile sync")
struct ProfileSyncTests {
    @Test func newUsersGetDefaultsOwnerParentRestrictedKid() throws {
        let result = ProfileSync.sync(homeUsers: try homeUsers(), ownerAccount: try account(), into: SettingsDocument())
        let profiles = result.document.profiles

        #expect(profiles.count == 4)
        let owner = try #require(profiles[PlexUserID("1001")])
        #expect(owner.role == .parent)
        #expect(owner.plexRestriction == .unrestricted)
        #expect(owner.displayName == "Owner")
        #expect(profiles[PlexUserID("1002")]?.role == .parent)  // unrestricted Home user
        let little = try #require(profiles[PlexUserID("1003")])
        #expect(little.role == .kid)
        #expect(little.plexRestriction == .littleKid)
        #expect(little.ceiling == .u)
        // Teen is by assignment only: a restricted user starts as a kid.
        #expect(profiles[PlexUserID("1004")]?.role == .kid)
        #expect(profiles[PlexUserID("1004")]?.plexRestriction == .teen)
    }

    @Test func existingEntriesKeepRoleAndOverridesWhileRestrictionRefreshes() throws {
        var doc = SettingsDocument()
        var teen = ProfileSettings.defaults(
            plexUserID: PlexUserID("1004"), displayName: "Old name", isOwner: false, restriction: .olderKid)
        teen.role = .teen
        teen.aiEnabled = true
        teen.rooms = [RoomID("lounge")]
        teen.setCeilingOverride(.pg)
        doc.profiles[PlexUserID("1004")] = teen

        let result = ProfileSync.sync(homeUsers: try homeUsers(), ownerAccount: try account(), into: doc)
        let synced = try #require(result.document.profiles[PlexUserID("1004")])

        #expect(synced.plexRestriction == .teen)  // refreshed from Plex
        #expect(synced.displayName == "Teen")
        #expect(synced.role == .teen)  // kept
        #expect(synced.aiEnabled)
        #expect(synced.rooms == [RoomID("lounge")])
        #expect(synced.ceilingOverride == .pg)  // below Plex's ceiling, so kept
    }

    @Test func anOverrideAbovePlexsNewCeilingIsClamped() throws {
        var doc = SettingsDocument()
        var kid = ProfileSettings.defaults(
            plexUserID: PlexUserID("1003"), displayName: "Little One", isOwner: false, restriction: .olderKid)
        kid.setCeilingOverride(.pg)
        doc.profiles[PlexUserID("1003")] = kid

        // Plex now says little kid (U): the PG override must not outlive that.
        let result = ProfileSync.sync(homeUsers: try homeUsers(), ownerAccount: try account(), into: doc)

        #expect(result.document.profiles[PlexUserID("1003")]?.ceiling == .u)
    }

    @Test func unknownRestrictedProfileFailsClosed() throws {
        let mystery = PlexHomeUser(
            id: "2001", uuid: "u", title: "Mystery", restricted: true, restrictionProfile: "future_profile")

        let result = ProfileSync.sync(
            homeUsers: [mystery], ownerAccount: try account(), into: SettingsDocument())
        let profile = try #require(result.document.profiles[PlexUserID("2001")])

        #expect(profile.role == .kid)
        #expect(profile.ceiling == .u)
    }

    @Test func ownerIsSetFromTheAccountAndPINStateReported() throws {
        let result = ProfileSync.sync(homeUsers: try homeUsers(), ownerAccount: try account(), into: SettingsDocument())

        #expect(result.ownerUserID == PlexUserID("1001"))
        #expect(result.document.household.ownerPlexUserID == PlexUserID("1001"))
        #expect(result.ownerHasPlexPIN == false)

        let protectedOwner = PlexHomeUser(id: "1001", uuid: "u", title: "Owner", admin: true, protected: true)
        let withPIN = ProfileSync.sync(
            homeUsers: [protectedOwner], ownerAccount: try account(), into: SettingsDocument())
        #expect(withPIN.ownerHasPlexPIN == true)
    }

    @Test func ownerNotListedGivesNoPINAnswerAndFallsBackToTheAccountID() throws {
        let other = PlexHomeUser(id: "3001", uuid: "u", title: "Someone")

        let result = ProfileSync.sync(homeUsers: [other], ownerAccount: try account(), into: SettingsDocument())

        #expect(result.ownerHasPlexPIN == nil)
        #expect(result.ownerUserID == PlexUserID("1001"))
    }

    @Test func theResultPassesDocumentValidation() throws {
        let result = ProfileSync.sync(homeUsers: try homeUsers(), ownerAccount: try account(), into: SettingsDocument())

        try result.document.validate()
    }
}
