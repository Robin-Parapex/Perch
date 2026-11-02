import Foundation
import PerchCore
import Testing

@testable import PerchPlex

@Suite("Plex models")
struct PlexModelTests {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    @Test func pinCreatedAndLinked() throws {
        let created = try PlexJSON.decode(PlexPin.self, from: Fixture.data("pin_created"))
        #expect(created.id == 987654321)
        #expect(created.code == "ABCD")
        #expect(created.authToken == nil)
        #expect(created.expiresAt != nil)
        let linked = try PlexJSON.decode(PlexPin.self, from: Fixture.data("pin_linked"))
        #expect(linked.authToken == "FAKE-TOKEN-1")
    }

    @Test func pinDateWithFractionalSeconds() throws {
        let pin = try PlexJSON.decode(
            PlexPin.self, from: json(#"{"id":1,"code":"A","expiresAt":"2026-11-02T10:15:00.123Z"}"#))
        #expect(pin.expiresAt != nil)
    }

    @Test func accountFromUser() throws {
        let a = try PlexJSON.decode(PlexAccount.self, from: Fixture.data("user"))
        #expect(a.id == 1001)
        #expect(a.uuid == "uuid-owner-0001")
        #expect(a.username == "owner")
        #expect(a.title == "Owner")
        #expect(a.authToken == "FAKE-TOKEN-1")
        #expect(a.hasPassword == true)
    }

    @Test func homeUsersFromFixtureAcceptsStringAndIntIDs() throws {
        let users = try PlexHomeUser.decodeList(from: Fixture.data("home_users"))
        #expect(users.map(\.id) == ["1001", "1002", "1003", "1004"])
        #expect(users[0].admin)
        #expect(users[1].protected)
    }

    @Test func homeUsersBareArray() throws {
        let users = try PlexHomeUser.decodeList(
            from: json(#"[{"id":7,"title":"A"},{"id":"8","title":"B"}]"#))
        #expect(users.map(\.id) == ["7", "8"])
    }

    @Test func homeUsersWrongShapeThrowsDecoding() {
        #expect(throws: PlexError.decoding) { try PlexHomeUser.decodeList(from: json(#"{"nope":1}"#)) }
    }

    private func user(restricted: Bool, profile: String?) throws -> PlexHomeUser {
        let p = profile.map { "\"\($0)\"" } ?? "null"
        let data = json(#"{"id":1,"title":"T","restricted":\#(restricted),"restrictionProfile":\#(p)}"#)
        return try PlexHomeUser.decodeList(from: json("[" + String(decoding: data, as: UTF8.self) + "]"))[0]
    }

    @Test(arguments: [
        ("little_kid", PlexRestriction.littleKid),
        ("older_kid", .olderKid),
        ("teen", .teen),
        ("mystery", .custom(allowedRatings: [])),
    ])
    func restrictedProfilesMap(profile: String, expected: PlexRestriction) throws {
        #expect(try user(restricted: true, profile: profile).restriction == expected)
    }

    @Test func restrictedWithoutProfileFailsClosed() throws {
        #expect(try user(restricted: true, profile: nil).restriction == .custom(allowedRatings: []))
        #expect(try user(restricted: true, profile: "").restriction == .custom(allowedRatings: []))
    }

    @Test func unrestrictedIsUnrestricted() throws {
        #expect(try user(restricted: false, profile: nil).restriction == .unrestricted)
    }

    @Test func fixtureRestrictions() throws {
        let users = try PlexHomeUser.decodeList(from: Fixture.data("home_users"))
        #expect(users.map(\.restriction) == [.unrestricted, .unrestricted, .littleKid, .teen])
    }

    @Test func switchResultReadsAuthToken() throws {
        let r = try PlexJSON.decode(PlexSwitchResult.self, from: Fixture.data("switch_ok"))
        #expect(r.authToken == "FAKE-TOKEN-PROFILE-1")
    }

    @Test func switchResultReadsLegacyToken() throws {
        let r = try PlexJSON.decode(PlexSwitchResult.self, from: Fixture.data("switch_ok_legacy"))
        #expect(r.authToken == "FAKE-TOKEN-PROFILE-1")
    }

    @Test func switchResultWithoutTokenFails() {
        #expect(throws: PlexError.decoding) {
            try PlexJSON.decode(PlexSwitchResult.self, from: json(#"{"id":1}"#))
        }
    }

    @Test func switchResultReadsXMLToken() throws {
        let xml = #"<?xml version="1.0" encoding="UTF-8"?><user id="1002" uuid="u" authenticationToken="FAKE-TOKEN-PROFILE-1"><subscription active="0"/></user>"#
        #expect(try PlexSwitchResult.decode(from: Data(xml.utf8)).authToken == "FAKE-TOKEN-PROFILE-1")
    }

    @Test func switchResultReadsJSONThroughDecode() throws {
        #expect(try PlexSwitchResult.decode(from: Fixture.data("switch_ok")).authToken == "FAKE-TOKEN-PROFILE-1")
    }

    @Test func switchResultWithoutTokenInXMLFails() {
        #expect(throws: PlexError.decoding) {
            try PlexSwitchResult.decode(from: Data(#"<user id="1002" authenticationToken=""/>"#.utf8))
        }
        #expect(throws: PlexError.decoding) { try PlexSwitchResult.decode(from: Data("not xml".utf8)) }
    }

    @Test func resourcesKeepOnlyServers() throws {
        let servers = try PlexResource.servers(from: Fixture.data("resources"))
        #expect(servers.map(\.clientIdentifier) == ["FAKE-MACHINE-LOUNGE", "FAKE-MACHINE-GARAGE"])
        #expect(servers[0].accessToken == "FAKE-SERVER-TOKEN-1")
        #expect(servers[0].owned)
    }

    @Test func connectionsSortLocalRemoteRelay() throws {
        let lounge = try PlexResource.servers(from: Fixture.data("resources"))[0]
        #expect(lounge.sortedConnections.map(\.tier) == [.local, .remote, .relay])
    }

    @Test func connectionsSortIPv4BeforeIPv6WithinTier() {
        func c(_ uri: String, local: Bool, relay: Bool = false, v6: Bool) -> PlexConnection {
            PlexConnection(
                protocol: "http", address: uri, port: 1, uri: uri, local: local, relay: relay, isIPv6: v6)
        }
        let r = PlexResource(
            name: "S", clientIdentifier: "S", provides: "server",
            connections: [
                c("relay", local: false, relay: true, v6: false),
                c("remote6", local: false, v6: true),
                c("local6", local: true, v6: true),
                c("remote4", local: false, v6: false),
                c("local4", local: true, v6: false),
            ])
        #expect(r.sortedConnections.map(\.uri) == ["local4", "local6", "remote4", "remote6", "relay"])
    }

    @Test func providesListMatchesServerExactly() {
        #expect(PlexResource(name: "", clientIdentifier: "a", provides: "client,server").isServer)
        #expect(!PlexResource(name: "", clientIdentifier: "a", provides: "client,player").isServer)
    }

    @Test func identityUnwrapsMediaContainer() throws {
        let i = try PlexServerIdentity.decode(from: Fixture.data("identity"))
        #expect(i.machineIdentifier == "FAKE-MACHINE-LOUNGE")
        #expect(i.version == "1.41.0.0")
    }

    @Test func sectionsUnwrapMediaContainer() throws {
        #expect(try PlexLibrarySummary.decode(from: Fixture.data("sections")).sectionCount == 3)
    }
}
