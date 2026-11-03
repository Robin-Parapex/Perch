import Foundation
import PerchCore
import Testing

@testable import PerchPlex

private let partner = PlexUserID("1002")

private func signedIn() async throws -> (SessionRig, PlexSession) {
    let rig = SessionRig()
    await rig.transport.scriptHealthyAccount()
    let session = rig.makeSession()
    try await session.signIn(accountToken: "TOKEN-OWNER")
    return (rig, session)
}

@Suite("Session generation and library context", .timeLimit(.minutes(1)))
struct PlexSessionGenerationTests {
    @Test func theContextCarriesTheServerTokenProfileAndMachine() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }

        let context = try await session.libraryContext()

        #expect(context.token == testServerToken)
        #expect(context.profileID == "1001")
        #expect(context.machineID == "FAKE-MACHINE-LOUNGE")
        #expect(context.baseURL == URL(string: "http://192.168.1.20:32400"))
        #expect(context.generation == (await session.currentGeneration()))
    }

    @Test func noContextWhenSignedOut() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        let session = rig.makeSession()
        await #expect(throws: PlexError.notSignedIn) { try await session.libraryContext() }
        #expect(await session.currentGeneration() == 0)
    }

    @Test func activatingBumpsTheGeneration() async throws {
        let rig = SessionRig()
        defer { rig.cleanup() }
        await rig.transport.scriptHealthyAccount()
        let session = rig.makeSession()
        let before = await session.currentGeneration()

        try await session.signIn(accountToken: "TOKEN-OWNER")

        #expect(await session.currentGeneration() > before)
    }

    @Test func switchingProfileBumpsTheGenerationAndChangesTheContext() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let first = try await session.libraryContext()
        await rig.transport.scriptSwitch(
            userID: "1002", .response(status: 200, body: Fixture.data("switch_ok")))

        try await session.switchProfile(to: partner, pin: "1234")

        let second = try await session.libraryContext()
        #expect(second.generation > first.generation)
        #expect(second.profileID == "1002")
        #expect(first.generation != (await session.currentGeneration()))
    }

    @Test func resumeBumpsTheGenerationWithoutActivate() async throws {
        let (rig, first) = try await signedIn()
        defer { rig.cleanup() }
        _ = first
        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        let session = rig.makeSession(transport: relaunch)
        #expect(await session.currentGeneration() == 0)

        #expect(await session.resume())

        let context = try await session.libraryContext()
        #expect(context.generation > 0)
        #expect(context.profileID == "1001")
    }

    @Test func signOutBumpsTheGenerationAndEndsTheContext() async throws {
        let (rig, session) = try await signedIn()
        defer { rig.cleanup() }
        let before = try await session.libraryContext()

        await session.signOut()

        #expect(await session.currentGeneration() > before.generation)
        await #expect(throws: PlexError.notSignedIn) { try await session.libraryContext() }
    }

    @Test func unrelatedPublishesDoNotBumpIt() async throws {
        let (rig, first) = try await signedIn()
        defer { rig.cleanup() }
        _ = first
        // Relaunch with plex.tv down: refreshing flips plexTVReachable and publishes a snapshot.
        let relaunch = FakeTransport()
        await relaunch.script(path: "/identity", fixture: "identity")
        let down = FakeTransport.Reply.failure(.notConnectedToInternet)
        for path in ["/api/v2/user", "/api/v2/home/users", "/api/v2/resources"] {
            await relaunch.script(path: path, down)
        }
        let session = rig.makeSession(transport: relaunch)
        #expect(await session.resume())
        let ready = await session.currentGeneration()

        await session.refreshFromPlexTV()

        #expect(await session.snapshot().plexTVReachable == false)
        #expect(await session.currentGeneration() == ready)
    }
}
