import Testing

@testable import PerchCore

@Suite("Profile switch policy")
struct ProfileSwitchPolicyTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let from: Role?
        let to: Role
        let protected: Bool
        let hasPIN: Bool
        let expected: SwitchRequirement
        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(name: "kid to adult without PIN", from: .kid, to: .parent, protected: false, hasPIN: false, expected: .adminPIN),
        Row(name: "kid to adult with PIN", from: .kid, to: .parent, protected: true, hasPIN: true, expected: .targetPlexPIN),
        Row(name: "kid to teen without PIN", from: .kid, to: .teen, protected: false, hasPIN: false, expected: .adminPIN),
        Row(name: "kid to kid", from: .kid, to: .kid, protected: false, hasPIN: false, expected: .none),
        Row(name: "kid to protected kid", from: .kid, to: .kid, protected: true, hasPIN: true, expected: .targetPlexPIN),
        Row(name: "adult to protected adult", from: .parent, to: .parent, protected: true, hasPIN: true, expected: .targetPlexPIN),
        Row(name: "adult to plain adult", from: .parent, to: .parent, protected: false, hasPIN: false, expected: .none),
        Row(name: "adult to kid", from: .parent, to: .kid, protected: false, hasPIN: false, expected: .none),
        Row(name: "teen to adult without PIN", from: .teen, to: .parent, protected: false, hasPIN: false, expected: .none),
        Row(name: "nothing resumed, no history", from: nil, to: .parent, protected: false, hasPIN: false, expected: .none),
        Row(name: "nothing resumed, no history, protected", from: nil, to: .parent, protected: true, hasPIN: true, expected: .targetPlexPIN),
    ]

    @Test(arguments: rows)
    func table(_ row: Row) {
        let result = ProfileSwitchPolicy.requirement(
            fromRole: row.from, toRole: row.to, targetIsProtected: row.protected, targetHasPlexPIN: row.hasPIN)
        #expect(result == row.expected)
    }

    private func settings(_ id: String, _ role: Role, pinRequiredToExit: Bool = false) -> ProfileSettings {
        ProfileSettings(plexUserID: PlexUserID(id), role: role, pinRequiredToExit: pinRequiredToExit)
    }

    @Test func aProfileChangedToKidThenLeavingRequiresAPIN() {
        var profile = settings("2", .parent)
        let adult = settings("1", .parent)
        #expect(
            ProfileSwitchPolicy.requirement(
                from: profile, fallbackRole: nil, to: adult, targetIsProtected: false, targetHasPlexPIN: false)
                == .none)
        profile.role = .kid  // changed in the wizard; pinRequiredToExit stays false
        #expect(
            ProfileSwitchPolicy.requirement(
                from: profile, fallbackRole: nil, to: adult, targetIsProtected: false, targetHasPlexPIN: false)
                == .adminPIN)
    }

    @Test func noCurrentProfileUsesTheLastProfilesRole() {
        let adult = settings("1", .parent)
        #expect(
            ProfileSwitchPolicy.requirement(
                from: nil, fallbackRole: .kid, to: adult, targetIsProtected: false, targetHasPlexPIN: false)
                == .adminPIN)
        #expect(
            ProfileSwitchPolicy.requirement(
                from: nil, fallbackRole: .kid, to: adult, targetIsProtected: true, targetHasPlexPIN: true)
                == .targetPlexPIN)
    }

    @Test func theCurrentProfileWinsOverTheStoredFallback() {
        let adult = settings("1", .parent)
        #expect(
            ProfileSwitchPolicy.requirement(
                from: settings("3", .parent), fallbackRole: .kid, to: adult, targetIsProtected: false,
                targetHasPlexPIN: false) == .none)
    }
}
