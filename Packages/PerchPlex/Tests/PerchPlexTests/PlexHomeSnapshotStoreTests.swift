import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "perch-snapshot-test-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func item(_ id: String, title: String = "T") -> MediaSummary {
    MediaSummary(id: id, kind: .film, title: title, certificate: "PG", viewOffsetMs: 1000)
}

private func rows(_ ids: [String], upNext: [String] = [], recent: [String] = []) -> PlexHomeRows {
    PlexHomeRows(
        continueWatching: ids.map { item($0) }, upNext: upNext.map { item($0) },
        recentlyAdded: recent.map { item($0) })
}

@Suite("Home snapshot store", .timeLimit(.minutes(1)))
struct PlexHomeSnapshotStoreTests {
    @Test func rowsRoundTripThroughTheFileForANewStore() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = rows(["1"], upNext: ["2"], recent: ["3", "4"])

        PlexHomeSnapshotStore(directory: directory).write(
            written, profileID: "1001", machineID: "M1")

        let reader = PlexHomeSnapshotStore(directory: directory)
        #expect(reader.read(profileID: "1001") == written)
        #expect(reader.machineID(profileID: "1001") == "M1")
        #expect(reader.read(profileID: "1001")?.row(id: "plex.recentlyAdded")?.items.count == 2)
    }

    @Test func aProfileNeverReadsAnotherProfilesFile() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlexHomeSnapshotStore(directory: directory)
        store.write(rows(["A"]), profileID: "1001", machineID: "M1")
        store.write(rows(["B"]), profileID: "1003", machineID: "M1")

        let fresh = PlexHomeSnapshotStore(directory: directory)
        #expect(fresh.read(profileID: "1001")?.continueWatching.items.map(\.id) == ["A"])
        #expect(fresh.read(profileID: "1003")?.continueWatching.items.map(\.id) == ["B"])
        #expect(fresh.read(profileID: "1002") == nil)
    }

    @Test func idsThatSanitiseToTheSameFileNameStillDoNotCross() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        PlexHomeSnapshotStore(directory: directory).write(
            rows(["slash"]), profileID: "a/b", machineID: "M1")

        let fresh = PlexHomeSnapshotStore(directory: directory)
        #expect(fresh.read(profileID: "a_b") == nil)
        #expect(fresh.read(profileID: "a/b")?.continueWatching.items.map(\.id) == ["slash"])
        // The file name holds no path separator.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == ["home-a_b.json"])
    }

    @Test func rowsAreCappedAtFortyItemsEach() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ids = (0..<60).map(String.init)
        let store = PlexHomeSnapshotStore(directory: directory)

        store.write(rows(ids, upNext: ids, recent: ids), profileID: "1001", machineID: "M1")

        let read = try #require(PlexHomeSnapshotStore(directory: directory).read(profileID: "1001"))
        #expect(read.continueWatching.items.count == 40)
        #expect(read.upNext.items.count == 40)
        #expect(read.recentlyAdded.items.count == 40)
        #expect(read.continueWatching.items.first?.id == "0")
    }

    @Test func deleteAllRemovesEveryProfilesFileAndTheMemoryCopy() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlexHomeSnapshotStore(directory: directory)
        store.write(rows(["A"]), profileID: "1001", machineID: "M1")
        store.write(rows(["B"]), profileID: "1002", machineID: "M1")
        #expect(store.read(profileID: "1001") != nil)

        store.deleteAll()

        #expect(store.read(profileID: "1001") == nil)
        #expect(store.read(profileID: "1002") == nil)
        #expect(PlexHomeSnapshotStore(directory: directory).read(profileID: "1002") == nil)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).isEmpty)
    }

    @Test func unreadableOrCorruptFilesReadAsNothing() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // The directory does not exist yet.
        #expect(PlexHomeSnapshotStore(directory: directory).read(profileID: "1001") == nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appending(path: "home-1001.json"))
        try Data().write(to: directory.appending(path: "home-1002.json"))

        let store = PlexHomeSnapshotStore(directory: directory)
        #expect(store.read(profileID: "1001") == nil)
        #expect(store.read(profileID: "1002") == nil)
        // A good write replaces the corrupt file.
        store.write(rows(["A"]), profileID: "1001", machineID: "M1")
        #expect(PlexHomeSnapshotStore(directory: directory).read(profileID: "1001") != nil)
    }

    @Test func aSnapshotHoldsNoTokenOrUrl() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        PlexHomeSnapshotStore(directory: directory).write(
            rows(["1"]), profileID: "1001", machineID: "M1")

        let text = String(
            decoding: try Data(contentsOf: directory.appending(path: "home-1001.json")), as: UTF8.self)
        #expect(!text.localizedCaseInsensitiveContains("token"))
        #expect(!text.contains("http"))
    }
}
