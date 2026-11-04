import Foundation
import Testing

@testable import PerchCore

@Suite struct PlaybackSourceTests {
    @Test func descriptionHidesHeaderValuesAndQuery() {
        let source = PlaybackSource(
            ratingKey: "42", title: "Film",
            url: URL(string: "https://plex.example/video/:/transcode/start.m3u8?X-Plex-Token=SECRETTOKEN")!,
            headers: ["X-Plex-Token": "SECRETVALUE", "Accept": "application/json"],
            decision: PlaybackDecision(method: .directPlay), sessionID: "s1")
        for text in [source.description, source.debugDescription, "\(source)"] {
            #expect(!text.contains("SECRETVALUE"))
            #expect(!text.contains("SECRETTOKEN"))
            #expect(!text.contains("?"))
            #expect(text.contains("/video/:/transcode/start.m3u8"))
            #expect(text.contains("X-Plex-Token") && text.contains("Accept"))
        }
    }
}

@Suite struct PlaybackLogTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("perch-log-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested/playback.jsonl")
    }

    private func entry(_ n: Int, outcome: PlaybackLogEntry.Outcome = .start, error: String? = nil)
        -> PlaybackLogEntry
    {
        PlaybackLogEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)), profileID: "p1",
            ratingKey: "\(n)", title: "Title \(n)", method: .directStream, reasons: ["r\(n)"],
            notes: ["n\(n)"], outcome: outcome, positionMs: n * 1000, startLatencyMs: 300, error: error)
    }

    @Test func roundTripCreatesDirectory() async {
        let url = tempFile()
        let log = PlaybackLog(fileURL: url)
        await log.append(entry(1))
        await log.append(entry(2, outcome: .stop))
        #expect(await log.entries() == [entry(1), entry(2, outcome: .stop)])
        // A fresh instance reads the same file.
        #expect(await PlaybackLog(fileURL: url).entries().map(\.ratingKey) == ["1", "2"])
        #expect(await log.entries(limit: 1).map(\.ratingKey) == ["2"])
    }

    @Test func trimsToNewest() async {
        let url = tempFile()
        let log = PlaybackLog(fileURL: url, maxEntries: 5)
        for n in 1...8 { await log.append(entry(n)) }
        #expect(await log.entries().map(\.ratingKey) == ["4", "5", "6", "7", "8"])
        let lines = try? String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines?.count == 5)
    }

    @Test func skipsCorruptLines() async throws {
        let url = tempFile()
        let first = PlaybackLog(fileURL: url)
        await first.append(entry(1))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not json\n".utf8))
        try handle.close()
        let second = PlaybackLog(fileURL: url)
        await second.append(entry(2))
        #expect(await second.entries().map(\.ratingKey) == ["1", "2"])
    }

    @Test func lastLinesFormatsNewestLast() async {
        let log = PlaybackLog(fileURL: tempFile())
        for n in 1...3 { await log.append(entry(n)) }
        let text = await log.lastLines(2)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("Title 2") && lines[1].contains("Title 3"))
        #expect(lines[1].contains("start") && lines[1].contains("directStream"))
        #expect(lines[1].contains("because r3") && lines[1].contains("notes n3"))
        #expect(await log.lastLines(0) == "")
    }

    @Test func failureBeforeADecisionHasNoMethodAndOldLinesStillDecode() async throws {
        let url = tempFile()
        // A line written before `method` became optional, then one with no method at all.
        let old = #"{"date":"2023-11-14T22:13:20Z","engine":"native","method":"directPlay","notes":[],"outcome":"start","ratingKey":"7","reasons":[],"title":"Old"}"#
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((old + "\n").utf8).write(to: url)
        let log = PlaybackLog(fileURL: url)
        await log.append(PlaybackLogEntry(ratingKey: "8", title: "New", outcome: .failure, error: "refused"))
        let entries = await log.entries()
        #expect(entries.map(\.ratingKey) == ["7", "8"])
        #expect(entries[0].method == .directPlay)
        #expect(entries[1].method == nil)
        #expect(await PlaybackLog(fileURL: url).entries().last?.method == nil)
        let last = await log.lastLines(1)
        #expect(last.contains("unknown") && !last.contains("directPlay"))
    }

    @Test func stripsQueriesFromErrors() async {
        let log = PlaybackLog(fileURL: tempFile())
        await log.append(
            entry(
                1, outcome: .failure,
                error: "Failed https://plex.example:32400/video/start.m3u8?X-Plex-Token=abc&x=1 then http://h/a?b=c."))
        let error = await log.entries().first?.error ?? ""
        #expect(!error.contains("abc") && !error.contains("?"))
        #expect(error.contains("https://plex.example:32400/video/start.m3u8"))
        #expect(error.contains("http://h/a"))
    }
}
