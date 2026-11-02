import Foundation
import Testing

@testable import PerchCore

@Suite struct SettingsTests {
    static func sampleDocument() -> SettingsDocument {
        var doc = SettingsDocument()
        doc.household.ownerPlexUserID = "123"
        doc.profiles["123"] = ProfileSettings.defaults(
            plexUserID: "123", displayName: "Robin", isOwner: true, restriction: .unrestricted)
        var kid = ProfileSettings.defaults(
            plexUserID: "456", displayName: "Sam", isOwner: false, restriction: .olderKid)
        kid.rooms = ["bedroom"]
        kid.seerrUserID = 7
        doc.profiles["456"] = kid
        doc.modules["seerr"] = ModuleSettings(enabled: true, config: ["baseURL": "https://seerr.local"])
        return doc
    }

    @Test func roundTrip() throws {
        let doc = Self.sampleDocument()
        let data = try JSONEncoder().encode(doc)
        #expect(try JSONDecoder().decode(SettingsDocument.self, from: data) == doc)
    }

    @Test func profilesEncodeAsObject() throws {
        let data = try JSONEncoder().encode(Self.sampleDocument())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profiles = try #require(json["profiles"] as? [String: Any])
        #expect(profiles["123"] != nil)
        #expect(profiles["456"] != nil)
        #expect(json["modules"] is [String: Any])
    }

    @Test func emptyDocumentDecodesToDefaults() throws {
        let doc = try JSONDecoder().decode(SettingsDocument.self, from: Data("{}".utf8))
        #expect(doc == SettingsDocument())
        #expect(doc.schemaVersion == SettingsDocument.currentSchemaVersion)
    }

    @Test func minimalProfileFailsSafe() throws {
        let p = try JSONDecoder().decode(ProfileSettings.self, from: Data(#"{"plexUserID":"9"}"#.utf8))
        #expect(p.plexUserID == "9")
        #expect(p.displayName == "")
        #expect(p.role == .kid)
        #expect(p.rooms.isEmpty)
        #expect(p.plexRestriction == .custom(allowedRatings: []))
        #expect(p.ceiling == .u)
        #expect(p.ceilingOverride == nil)
        #expect(p.seerrUserID == nil)
        #expect(!p.pinRequiredToExit)
        #expect(!p.aiEnabled)
        #expect(p.aiLevel == 0)
        #expect(p.yearInReviewEnabled)
    }

    @Test func unknownFieldsIgnored() throws {
        let json = #"{"schemaVersion":1,"future":{"a":1},"profiles":{"1":{"plexUserID":"1","wat":true}}}"#
        let doc = try JSONDecoder().decode(SettingsDocument.self, from: Data(json.utf8))
        #expect(doc.profiles["1"]?.plexUserID == "1")
    }

    @Test func profileMissingIDIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProfileSettings.self, from: Data("{}".utf8))
        }
    }

    @Test func defaultsByRestriction() {
        func make(_ owner: Bool, _ r: PlexRestriction) -> ProfileSettings {
            .defaults(plexUserID: "1", displayName: "X", isOwner: owner, restriction: r)
        }
        let owner = make(true, .littleKid)
        #expect(owner.role == .parent && !owner.pinRequiredToExit)
        let open = make(false, .unrestricted)
        #expect(open.role == .parent && !open.pinRequiredToExit)
        let restricted: [PlexRestriction] = [
            .littleKid, .olderKid, .teen, .custom(allowedRatings: ["PG"]),
        ]
        for r in restricted {
            let p = make(false, r)
            #expect(p.role == .kid)
            #expect(p.role != .teen)
            #expect(p.pinRequiredToExit)
            #expect(!p.aiEnabled && p.aiLevel == 0 && p.yearInReviewEnabled)
        }
    }

    @Test func overrideLowersButNeverRaises() {
        var p = ProfileSettings.defaults(
            plexUserID: "1", displayName: "", isOwner: false, restriction: .olderKid)
        p.setCeilingOverride(.eighteen)
        #expect(p.ceilingOverride == .pg)
        #expect(p.ceiling == .pg)
        p.setCeilingOverride(.u)
        #expect(p.ceiling == .u)
        p.setCeilingOverride(nil)
        #expect(p.ceilingOverride == nil)
        #expect(p.ceiling == .pg)
    }

    @Test func householdLowest() {
        var doc = SettingsDocument()
        #expect(doc.householdLowestCeiling == .u)
        doc.profiles["1"] = .defaults(
            plexUserID: "1", displayName: "", isOwner: true, restriction: .unrestricted)
        #expect(doc.householdLowestCeiling == .eighteen)
        doc.profiles["2"] = .defaults(
            plexUserID: "2", displayName: "", isOwner: false, restriction: .teen)
        #expect(doc.householdLowestCeiling == .twelveA)
    }

    @Test func permissionContextMapping() {
        var p = ProfileSettings(plexUserID: "5", role: .teen)
        p.rooms = ["a", "b"]
        p.aiEnabled = true
        p.aiLevel = 2
        p.yearInReviewEnabled = false
        let c = p.permissionContext(isPINFresh: true)
        #expect(c.role == .teen && c.plexUserID == "5" && c.ownRooms == ["a", "b"])
        #expect(c.isPINFresh && c.aiEnabled && c.aiLevel == 2 && !c.yearInReviewEnabled)
    }

    @Test func validateRejectsSecretLikeKeys() throws {
        for key in ["apiKey", "Token", "client_secret", "password"] {
            var doc = SettingsDocument()
            doc.modules["m"] = ModuleSettings(enabled: true, config: [key: "x"])
            #expect(throws: SettingsError.secretLikeConfigKey(module: "m", key: key)) {
                try doc.validate()
            }
        }
        var ok = SettingsDocument()
        ok.modules["m"] = ModuleSettings(enabled: true, config: ["baseURL": "https://x"])
        try ok.validate()
    }

    @Test func storeRoundTripAndMissingValue() async throws {
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(store: kv)
        #expect(try await store.load() == SettingsDocument())
        let doc = Self.sampleDocument()
        try await store.save(doc)
        let other = SettingsStore(store: kv)
        #expect(try await other.load() == doc)
        try await other.update { $0.household.ownerPlexUserID = "999" }
        #expect(await other.document.household.ownerPlexUserID == "999")
        #expect(try await SettingsStore(store: kv).load().household.ownerPlexUserID == "999")
    }

    @Test func saveRejectsSecretLikeKey() async throws {
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(store: kv)
        var doc = SettingsDocument()
        doc.modules["m"] = ModuleSettings(enabled: true, config: ["apiKey": "x"])
        await #expect(throws: SettingsError.self) { try await store.save(doc) }
        #expect(kv.data(forKey: "perch.settings.v1") == nil)
    }

    @Test func saveRefusesOversizedDocument() async throws {
        let kv = InMemoryKeyValueStore()
        let store = SettingsStore(store: kv)
        var doc = SettingsDocument()
        doc.modules["m"] = ModuleSettings(
            enabled: true, config: ["baseURL": String(repeating: "a", count: 250_000)])
        do {
            try await store.save(doc)
            Issue.record("expected tooLarge")
        } catch SettingsError.tooLarge(let bytes) {
            #expect(bytes > 150_000)
        }
        #expect(kv.data(forKey: "perch.settings.v1") == nil)
        #expect(SettingsStore.maxBytes == 150_000)
    }

    @Test func largeCorruptValueIsKeptTruncated() async {
        let kv = InMemoryKeyValueStore()
        let garbage = Data(repeating: UInt8(ascii: "x"), count: 100_000)
        kv.set(garbage, forKey: "perch.settings.v1")
        let store = SettingsStore(store: kv)
        _ = try? await store.load()
        await store.discardCorruptDocument()
        #expect(kv.data(forKey: "perch.settings.v1.corrupt")?.count == 32_768)
        #expect(kv.data(forKey: "perch.settings.v1") == nil)
    }

    @Test func corruptValueThrowsAndIsUntouched() async throws {
        let kv = InMemoryKeyValueStore()
        let garbage = Data("not json {{{".utf8)
        kv.set(garbage, forKey: "perch.settings.v1")
        let store = SettingsStore(store: kv)
        await #expect(throws: SettingsError.corrupt) { try await store.load() }
        _ = await store.document
        #expect(kv.data(forKey: "perch.settings.v1") == garbage)
    }

    @Test func corruptValueBlocksSaveUntilDiscarded() async throws {
        let kv = InMemoryKeyValueStore()
        let garbage = Data("not json {{{".utf8)
        kv.set(garbage, forKey: "perch.settings.v1")
        let store = SettingsStore(store: kv)
        await #expect(throws: SettingsError.corrupt) {
            try await store.update { $0.household.ownerPlexUserID = "1" }
        }
        await #expect(throws: SettingsError.corrupt) { try await store.save(SettingsDocument()) }
        #expect(kv.data(forKey: "perch.settings.v1") == garbage)
        await store.discardCorruptDocument()
        #expect(kv.data(forKey: "perch.settings.v1.corrupt") == garbage)
        #expect(kv.data(forKey: "perch.settings.v1") == nil)
        #expect(await store.document == SettingsDocument())
        try await store.update { $0.household.ownerPlexUserID = "1" }
        #expect(try await SettingsStore(store: kv).load().household.ownerPlexUserID == "1")
    }

    @Test func exportContainsNoSecret() async throws {
        let secrets = InMemorySecretStore()
        try secrets.setString("sk-test-SECRET-1234", for: SecretKey.module("seerr", "apiKey"))
        let store = SettingsStore(store: InMemoryKeyValueStore())
        try await store.update {
            $0.modules["seerr"] = ModuleSettings(
                enabled: true, config: ["baseURL": "https://seerr.local"])
        }
        let data = try await store.exportData()
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("SECRET"))
        #expect(text.contains("baseURL"))
    }
}
