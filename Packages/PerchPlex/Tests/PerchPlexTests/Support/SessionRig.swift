import Foundation
import PerchCore

@testable import PerchPlex

let testIdentity = PlexClientIdentity(clientIdentifier: "TEST-CLIENT", version: "1.0")
let testEndpoints = PlexEndpoints(identity: testIdentity)

/// Fixed "now" for lockout arithmetic.
let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

func isoDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// Short timings with a real sleep: the prober races probes against sleeps, so a no-op sleep would
/// make every timeout fire at once.
let fastTiming = ConnectionProber.Timing(
    localTimeout: .milliseconds(400), remoteTimeout: .milliseconds(400), grace: .milliseconds(150),
    sleep: { try await Task.sleep(for: $0) })

/// A `PlexSession` over in-memory stores. Make a second session over the same stores with
/// `makeSession(transport:)` to model a relaunch.
struct SessionRig {
    let transport: FakeTransport
    let secrets = InMemorySecretStore()
    let settings = SettingsStore(store: InMemoryKeyValueStore())
    let defaults: UserDefaults
    private let suite: String

    init(transport: FakeTransport = FakeTransport()) {
        self.transport = transport
        suite = "perch.tests.session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    func makeSession(
        transport: (any PlexTransport)? = nil, adminPIN: AdminPIN? = nil,
        now: @escaping NowProvider = { fixedNow }
    ) -> PlexSession {
        PlexSession(
            transport: transport ?? self.transport, identity: testIdentity, secrets: secrets,
            defaults: UserDefaults(suiteName: suite)!, settings: settings, adminPIN: adminPIN,
            proberTiming: fastTiming, now: now)
    }

    func cleanup() { defaults.removePersistentDomain(forName: suite) }

    func lockout() -> PINLockout? {
        defaults.data(forKey: PlexSession.DefaultsKey.profilePINLockout)
            .flatMap { try? JSONDecoder().decode(PINLockout.self, from: $0) }
    }
}

extension FakeTransport {
    /// A healthy plex.tv and one healthy local server (single-server resources).
    /// First matching rule wins in `FakeTransport`, so a test that needs a fault passes it here.
    func scriptHealthyAccount(
        resources: String = "resources_single", userStatus: Int = 200, sectionsStatus: Int = 200,
        identityFailure: URLError.Code? = nil
    ) {
        script(path: "/api/v2/user", fixture: "user", status: userStatus)
        script(path: "/api/v2/home/users", fixture: "home_users")
        script(path: "/api/v2/resources", fixture: resources)
        if let identityFailure {
            script(path: "/identity", .failure(identityFailure))
        } else {
            script(path: "/identity", fixture: "identity")
        }
        script(path: "/library/sections", fixture: "sections", status: sectionsStatus)
    }

    /// Switch endpoint for one Home user.
    func scriptSwitch(userID: String, _ reply: Reply) {
        script(path: "/api/home/users/\(userID)/switch", method: "POST", reply)
    }
}
