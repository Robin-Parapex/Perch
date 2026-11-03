import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let sectionPath = "/library/sections/1/all"

private func items(_ ids: ClosedRange<Int>) -> String {
    ids.map { #"{"ratingKey":"\#($0)","type":"movie","title":"T\#($0)"}"# }.joined(separator: ",")
}

private func page(size: Int, total: Int, _ ids: ClosedRange<Int>?) -> String {
    let body = ids.map { items($0) } ?? ""
    return #"{"MediaContainer":{"size":\#(size),"totalSize":\#(total),"offset":0,"Metadata":[\#(body)]}}"#
}

private func query(_ request: URLRequest, _ name: String) -> String? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == name }?.value
}

@Suite("Section pager", .timeLimit(.minutes(1)))
struct PlexSectionPagerTests {
    @Test func pagesFiftyThenOneHundredAndStopsOnAnEmptyPage() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: sectionPath, json: page(size: 3, total: 137, 1...3))
        await rig.transport.script(path: sectionPath, json: page(size: 2, total: 137, 4...5))
        await rig.transport.script(path: sectionPath, json: page(size: 0, total: 137, nil))
        let pager = await rig.library.pager(sectionID: "1", sort: "titleSort")

        let first = try await pager.nextPage()
        let second = try await pager.nextPage()
        #expect(await pager.isFinished == false)
        let third = try await pager.nextPage()

        #expect(first.map(\.id) == ["1", "2", "3"])
        #expect(second.map(\.id) == ["4", "5"])
        #expect(third.isEmpty)
        #expect(await pager.isFinished)
        let requests = await rig.transport.requests(forPath: sectionPath)
        #expect(requests.map { query($0, "X-Plex-Container-Start") } == ["0", "3", "5"])
        #expect(requests.map { query($0, "X-Plex-Container-Size") } == ["50", "100", "100"])
        #expect(requests.allSatisfy { query($0, "sort") == "titleSort" })
        // Finished: another call sends nothing.
        #expect(try await pager.nextPage().isEmpty)
        #expect(await rig.transport.requests(forPath: sectionPath).count == 3)
    }

    @Test func stopsWhenTheTotalIsReached() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: sectionPath, json: page(size: 3, total: 5, 1...3))
        await rig.transport.script(path: sectionPath, json: page(size: 2, total: 5, 4...5))
        let pager = await rig.library.pager(sectionID: "1", sort: nil)

        _ = try await pager.nextPage()
        _ = try await pager.nextPage()

        #expect(await pager.isFinished)
        #expect(await pager.totalCount == 5)
        #expect(try await pager.nextPage().isEmpty)
        #expect(await rig.transport.requests(forPath: sectionPath).count == 2)
        let last = try #require(await rig.transport.requests(forPath: sectionPath).last)
        #expect(query(last, "sort") == nil)
    }

    @Test func theNextOffsetFollowsTheServersRowCountNotTheDecodedItems() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        // Two rows returned, one without a rating key (dropped when mapped).
        let json = #"""
            {"MediaContainer":{"size":2,"totalSize":9,"Metadata":[
            {"ratingKey":"1","type":"movie","title":"A"},{"type":"movie","title":"No key"}]}}
            """#
        await rig.transport.script(path: sectionPath, json: json)
        let pager = await rig.library.pager(sectionID: "1", sort: nil)

        let first = try await pager.nextPage()
        _ = try await pager.nextPage()

        #expect(first.map(\.id) == ["1"])
        let requests = await rig.transport.requests(forPath: sectionPath)
        #expect(query(requests[1], "X-Plex-Container-Start") == "2")
    }

    @Test func aFailedPageKeepsThePosition() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: sectionPath, json: "", status: 500)
        await rig.transport.script(path: sectionPath, json: page(size: 3, total: 3, 1...3))
        let pager = await rig.library.pager(sectionID: "1", sort: nil)

        await #expect(throws: PlexError.http(500)) { try await pager.nextPage() }
        let retry = try await pager.nextPage()

        #expect(retry.map(\.id) == ["1", "2", "3"])
        let requests = await rig.transport.requests(forPath: sectionPath)
        #expect(requests.map { query($0, "X-Plex-Container-Start") } == ["0", "0"])
    }

    @Test func aPagerFromBeforeAProfileSwitchThrowsInsteadOfPagingTheNewProfile() async throws {
        let rig = try await LibraryRig.make()
        defer { rig.cleanup() }
        await rig.transport.script(path: sectionPath, json: page(size: 3, total: 137, 1...3))
        let pager = await rig.library.pager(sectionID: "1", sort: nil)
        _ = try await pager.nextPage()
        await rig.sessionRig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))
        try await rig.session.switchProfile(to: PlexUserID("1002"), pin: "1234")
        let sent = await rig.transport.requests.count

        await #expect(throws: CancellationError.self) { try await pager.nextPage() }

        #expect(await rig.transport.requests.count == sent)
    }
}
