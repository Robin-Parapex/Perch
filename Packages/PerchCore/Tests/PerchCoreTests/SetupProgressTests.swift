import Foundation
import Testing

@testable import PerchCore

@Suite("Setup progress")
struct SetupProgressTests {
    @Test func oneServerSkipsChooseServer() {
        let one = SetupProgress(serverCount: 1)
        #expect(one.steps == [.welcome, .connectPlex, .adminPIN, .profiles, .addLater, .done])
        let none = SetupProgress(serverCount: 0)
        #expect(none.steps == one.steps)
        let two = SetupProgress(serverCount: 2)
        #expect(two.steps == [.welcome, .connectPlex, .chooseServer, .adminPIN, .profiles, .addLater, .done])
    }

    @Test func nextAndPreviousFollowTheApplicableSteps() {
        let one = SetupProgress(serverCount: 1)
        #expect(one.next(after: .connectPlex) == .adminPIN)
        #expect(one.previous(before: .adminPIN) == .connectPlex)
        #expect(one.previous(before: .welcome) == nil)
        #expect(one.next(after: .done) == nil)
        let two = SetupProgress(serverCount: 3)
        #expect(two.next(after: .connectPlex) == .chooseServer)
        #expect(two.previous(before: .adminPIN) == .chooseServer)
    }

    @Test(arguments: [
        (SetupStep.welcome, true), (.connectPlex, false), (.chooseServer, true), (.adminPIN, false),
        (.profiles, true), (.addLater, true), (.done, false),
    ])
    func skipTable(step: SetupStep, expected: Bool) {
        #expect(SetupProgress().canSkip(step) == expected)
    }

    @Test(arguments: [
        (AdminPINSource.perch, true, true), (.plexOwner, true, true),
        (.perch, false, false), (.plexOwner, false, false),
        (.setupRequired, true, false), (.setupRequired, false, false),
        (.unavailable, true, false), (.unavailable, false, false),
    ])
    func finishTable(source: AdminPINSource, verified: Bool, expected: Bool) {
        var progress = SetupProgress(adminPINSource: source)
        if verified { progress.markAdminPINVerified() }
        #expect(progress.canFinish == expected)
    }

    @Test func cannotLeaveAdminPINUnverifiedOrSkipIt() {
        var progress = SetupProgress(serverCount: 1, adminPINSource: .plexOwner, current: .adminPIN)
        let r1 = progress.advance()
        #expect(!r1)
        let r2 = progress.skip()
        #expect(!r2)
        #expect(progress.current == .adminPIN)
        progress.markAdminPINVerified()
        let r3 = progress.advance()
        #expect(r3)
        #expect(progress.current == .profiles)
    }

    @Test func cannotReachDoneWithoutAWorkingAdminPIN() {
        var progress = SetupProgress(serverCount: 1, adminPINSource: .setupRequired, current: .addLater)
        let r4 = progress.advance()
        #expect(!r4)
        let r5 = progress.skip()
        #expect(!r5)
        progress.adminPINSource = .perch
        let r6 = progress.advance()
        #expect(!r6)
        progress.markAdminPINVerified()
        let r7 = progress.skip()
        #expect(r7)
        #expect(progress.current == .done)
        let r8 = progress.advance()
        #expect(!r8)
    }

    @Test func walkForwardAndBack() {
        var progress = SetupProgress(serverCount: 2, adminPINSource: .perch)
        let r9 = progress.advance()
        #expect(r9 && progress.current == .connectPlex)
        let r10 = progress.advance()
        #expect(r10 && progress.current == .chooseServer)
        let r11 = progress.goBack()
        #expect(r11 && progress.current == .connectPlex)
        let r12 = progress.goBack()
        #expect(r12 && progress.current == .welcome)
        let r13 = progress.goBack()
        #expect(!r13)
    }

    @Test func backAtStartDependsOnRerun() {
        #expect(SetupProgress().backAtStart == .leaveApp)
        #expect(SetupProgress(isRerun: true).backAtStart == .returnHome)
    }

    @Test func addLaterRegistryKeepsOrderAndReplaces() {
        let registry = AddLaterRegistry()
        registry.register(AddLaterEntry(moduleID: "trakt", title: "Trakt", order: 20))
        registry.register(AddLaterEntry(moduleID: "seerr", title: "Requests", order: 10))
        registry.register(AddLaterEntry(moduleID: "ha", title: "Home Assistant", order: 20))
        registry.register(AddLaterEntry(moduleID: "trakt", title: "Trakt scrobbling", order: 20))
        let entries = registry.entries()
        #expect(entries.map(\.title) == ["Requests", "Trakt scrobbling", "Home Assistant"])
        #expect(entries.allSatisfy { $0.detail == "Coming soon" })
    }

    @Test func setupCompleteFlagRoundTrips() {
        let store = InMemoryKeyValueStore()
        let flag = SetupCompletion(store: store)
        #expect(!flag.isComplete)
        flag.setComplete(true)
        #expect(flag.isComplete)
        #expect(store.data(forKey: "perch.setupComplete") != nil)
        flag.setComplete(false)
        #expect(!flag.isComplete)
    }
}
