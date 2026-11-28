import Foundation
import SlackRemoteCore

/// The PoC command can verify saved sessions while the production API is being implemented.
@MainActor
public final class WebKitPoC {
    private let pool: SessionPool?

    public init(pool: SessionPool?) {
        self.pool = pool
    }

    public func handle(_ request: HelperProtocol.Request) async -> (stdout: Data, stderr: Data, status: Int32) {
        guard let pool else { return failure("Accounts file unreadable.") }
        let arguments = Array(request.arguments.dropFirst())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            if arguments == ["accounts"] {
                return (try encoder.encode(pool.records) + Data([0x0a]), Data(), 0)
            }
            guard arguments.count == 4 || arguments.count == 6,
                  Array(arguments.prefix(3)) == ["call", "auth.test", "--team"],
                  arguments.count == 4 || arguments.suffix(2).elementsEqual(["--transport", "native"]),
                  let team = TeamID(arguments[3]) else {
                return failure("Usage: slack-remote webkit-poc accounts or webkit-poc call auth.test --team <team>")
            }
            guard let (record, session) = pool.session(for: team), record.state == .active else {
                return failure("No signed-in account for that workspace.")
            }
            let start = ContinuousClock.now
            try await session.prepare()
            guard let store = session.dataStore, let config = try await session.localConfig().teams[team.rawValue] else {
                return failure("The Slack session has no local configuration for this workspace.")
            }
            let identity = try await SignInAPI.identity(for: config, in: store)
            let elapsed = start.duration(to: .now).components
            let response = Diagnostic(response: .init(ok: identity.ok, user_id: identity.user),
                                      elapsedMs: elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000)
            return (try encoder.encode(response) + Data([0x0a]), Data(), identity.ok ? 0 : 1)
        } catch {
            return failure("The Slack request failed.")
        }
    }

    private struct Diagnostic: Encodable {
        struct Response: Encodable {
            let ok: Bool
            let user_id: UserID?
        }
        let response: Response
        let elapsedMs: Int64
    }

    private func failure(_ message: String) -> (Data, Data, Int32) {
        (Data(), Data((message + "\n").utf8), 1)
    }
}
