import Darwin
import Foundation
import SlackRemoteCore

private struct PoCAccount: Codable {
    struct Team: Codable {
        let id: String
        let name: String
        let url: String
        let userID: String
    }

    let storeID: UUID
    let teams: [Team]
}

@MainActor
public final class WebKitPoC {
    private static let accountsURL = HelperProtocol.socketURL.deletingLastPathComponent()
        .appendingPathComponent("poc-accounts.json")
    private static let usage = """
        Usage: slack-remote webkit-poc accounts
               slack-remote webkit-poc call <method> --team <id> [--transport page|native] [--param key=value]...
        """

    private var accounts: [PoCAccount] = []
    private var sessions: [UUID: Task<SlackSession, Error>] = [:]
    private var signIn: SignInWindowController?
    private var accountsLoadFailed = false

    public init() {}

    public func restoreAccounts() {
        do {
            accounts = try JSONDecoder().decode([PoCAccount].self, from: Data(contentsOf: Self.accountsURL))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            accountsLoadFailed = true
            NSLog("SlackRemote could not read PoC accounts")
            return
        }
        for account in accounts { startSession(for: account.storeID) }
    }

    public var teamLabels: [String] {
        accounts.flatMap(\.teams).map { "\($0.name) · \($0.userID)" }
    }

    public func showSignIn() {
        if signIn == nil {
            signIn = SignInWindowController(completed: { [weak self] storeID, config in
                self?.addAccount(storeID: storeID, config: config)
            }, closed: { [weak self] in
                self?.signIn = nil
            })
        }
        signIn?.show()
    }

    private func addAccount(storeID: UUID, config: LocalConfig) {
        let teams = config.teams.values.sorted { $0.id < $1.id }.map {
            PoCAccount.Team(id: $0.id, name: $0.name, url: $0.url, userID: $0.userID)
        }
        let updated = accounts + [PoCAccount(storeID: storeID, teams: teams)]
        do {
            guard !accountsLoadFailed else { throw CocoaError(.fileWriteUnknown) }
            try save(updated)
            accounts = updated
            startSession(for: storeID)
        } catch {
            NSLog("SlackRemote could not save the new PoC account")
        }
    }

    private func save(_ accounts: [PoCAccount]) throws {
        let url = Self.accountsURL
        let directory = url.deletingLastPathComponent()
        let data = try JSONEncoder().encode(accounts)
        // The helper owns and holds a lock on this 0700 directory for its lifetime.
        let staging = directory.appendingPathComponent(".poc-accounts-\(UUID().uuidString)")
        let files = FileManager.default
        defer { try? files.removeItem(at: staging) }
        guard files.createFile(atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(staging.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func startSession(for storeID: UUID) {
        guard sessions[storeID] == nil else { return }
        sessions[storeID] = Task {
            let session = SlackSession(storeID: storeID)
            do {
                try await session.loadIdle()
                if try await !session.localConfig().teams.isEmpty { return session }
            } catch {
                // The full client can provide the storage origin if the idle document can't.
            }
            NSLog("SlackRemote PoC local config unavailable in idle document, loading full client")
            try await session.loadClient()
            return session
        }
    }

    public func handle(_ request: HelperProtocol.Request) async -> (stdout: Data, stderr: Data, status: Int32) {
        do {
            if request.arguments == ["webkit-poc", "accounts"] {
                guard !accountsLoadFailed else { return failure("Could not read PoC accounts.") }
                return (try JSONEncoder().encode(accounts) + Data([10]), Data(), 0)
            }
            guard let call = Call(request.arguments) else { return failure(Self.usage, status: 2) }
            guard let account = accounts.first(where: { $0.teams.contains { $0.id == call.team } }),
                  let sessionTask = sessions[account.storeID] else {
                return failure("Team is not recorded. Run slack-remote webkit-poc accounts.")
            }
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "slack-remote command")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let start = DispatchTime.now().uptimeNanoseconds
            let session = try await sessionTask.value
            let result = try await execute(call, in: session)
            let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let body = (try? JSONSerialization.jsonObject(with: result.body, options: .fragmentsAllowed))
                ?? String(decoding: result.body, as: UTF8.self)
            var output: [String: Any] = [
                "transport": call.transport.rawValue,
                "status": result.status,
                "elapsedMs": elapsed,
                "response": body,
            ]
            output["retryAfter"] = result.retryAfter
            let json = try JSONSerialization.data(withJSONObject: output, options: [.withoutEscapingSlashes])
            let safe = String(decoding: json, as: UTF8.self)
                .replacingOccurrences(of: #"xox[cd]-[A-Za-z0-9%._~+/=-]+"#, with: "[redacted]",
                                      options: .regularExpression)
            return (Data((safe + "\n").utf8), Data(), 0)
        } catch TransportError.unknownTeam {
            return failure("Team is no longer available in the Slack browser session.")
        } catch TransportError.pageFetchFailed {
            return failure("Slack page fetch failed. Try --transport native.")
        } catch {
            // WebKit and networking errors can contain request details.
            return failure("Slack browser session or API request failed.")
        }
    }

    private func execute(_ call: Call, in session: SlackSession) async throws -> TransportResponse {
        let post = call.transport == .page ? pagePost : nativePost
        do {
            let response = try await post(session, call.team, call.method, call.params)
            let body = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any]
            if !session.isIdle || call.method != "auth.test" || body?["error"] as? String != "invalid_auth" {
                return response
            }
        } catch {
            // A failed fetch may have reached Slack. Only retry the read-only auth probe.
            guard session.isIdle, call.method == "auth.test" else { throw error }
        }
        NSLog("SlackRemote PoC idle API probe failed, loading full client")
        try await session.loadClient()
        return try await post(session, call.team, call.method, call.params)
    }

    private func failure(_ message: String, status: Int32 = 1) -> (stdout: Data, stderr: Data, status: Int32) {
        (Data(), Data((message + "\n").utf8), status)
    }

    private struct Call {
        enum Transport: String { case page, native }

        let method: String
        let team: String
        let transport: Transport
        let params: [String: String]

        init?(_ arguments: [String]) {
            guard arguments.count >= 3, arguments[1] == "call" else { return nil }
            method = arguments[2]
            let methodParts = method.split(separator: ".", omittingEmptySubsequences: false)
            guard !methodParts.isEmpty, methodParts.allSatisfy({ part in
                !part.isEmpty && part.utf8.allSatisfy {
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
                }
            }) else { return nil }

            var team: String?
            var transport = Transport.page
            var params: [String: String] = [:]
            var options = arguments.dropFirst(3).makeIterator()
            while let option = options.next() {
                guard let value = options.next() else { return nil }
                switch option {
                case "--team":
                    team = value
                case "--transport":
                    guard let chosen = Transport(rawValue: value) else { return nil }
                    transport = chosen
                case "--param":
                    guard let equals = value.firstIndex(of: "="), equals != value.startIndex else { return nil }
                    params[String(value[..<equals])] = String(value[value.index(after: equals)...])
                default:
                    return nil
                }
            }
            guard let team, !team.isEmpty else { return nil }
            self.team = team
            self.transport = transport
            self.params = params
        }
    }
}
