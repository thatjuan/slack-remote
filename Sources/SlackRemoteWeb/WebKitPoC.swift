import AppKit
import SlackRemoteCore

enum WebKitPoCError: String, Error {
    case missingConfig = "The Slack session has no local configuration for this workspace."
    case navigationFailed = "The Slack session could not load."
    case invalidWorkspaceURL = "The recorded workspace does not have a valid Slack HTTPS URL."
    case invalidResponse = "Slack returned an invalid transport response."
    case pageBlocked = "The page transport could not access any Slack API endpoint."
    case networkFailed = "The Slack request failed."
    case unknownTeam = "No account is recorded for that team. Run webkit-poc accounts."
    case usage = """
        Usage: slack-remote webkit-poc accounts
               slack-remote webkit-poc call <method> --team <team> [--transport page|native] [--param key=value]...
        """
}

@MainActor
public final class WebKitPoC {
    private var accounts: [AccountRecord] = []
    private var sessions: [UUID: SlackSession] = [:]
    private var signIn: SignInWindowController?

    public init() {}

    public var teamTitles: [String] {
        accounts.flatMap { $0.teams.map { "\($0.name) · \($0.userID)" } }
    }

    public func start() {
        do {
            accounts = try AccountRecord.read()
            for account in accounts { startSession(for: account.storeID) }
        } catch {
            NSLog("SlackRemote could not read its PoC accounts.")
        }
    }

    public func addAccount() {
        if signIn == nil {
            signIn = SignInWindowController { [weak self] account in
                guard let self else { return }
                signIn = nil
                guard let account else { return }
                do {
                    try AccountRecord.append(account)
                    accounts.append(account)
                    startSession(for: account.storeID)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "SlackRemote could not save the PoC account."
                    alert.runModal()
                }
            }
        }
        signIn?.open()
    }

    public func handle(_ request: HelperProtocol.Request) async -> (stdout: Data, stderr: Data, status: Int32) {
        do {
            let arguments = request.arguments.dropFirst()
            if arguments.elementsEqual(["accounts"]) {
                return (try JSONEncoder().encode(accounts) + Data([0x0A]), Data(), 0)
            }
            let call = try Call(arguments)
            let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "slack-remote command")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            return (try await run(call), Data(), 0)
        } catch {
            let reason = error as? WebKitPoCError ?? .networkFailed
            return (Data(), Data((reason.rawValue + "\n").utf8), 1)
        }
    }

    private func startSession(for storeID: UUID) {
        guard sessions[storeID] == nil else { return }
        let session = SlackSession(storeID: storeID)
        sessions[storeID] = session
        Task {
            do { try await session.prepare() }
            catch { NSLog("SlackRemote could not load a PoC browser profile.") }
        }
    }

    private func run(_ call: Call) async throws -> Data {
        guard let account = accounts.first(where: { $0.teams.contains { $0.id == call.team } }),
              let session = sessions[account.storeID] else { throw WebKitPoCError.unknownTeam }
        let start = DispatchTime.now().uptimeNanoseconds
        try await session.prepare()

        let reply: TransportResponse
        switch call.transport {
        case .page:
            do {
                reply = try await pagePost(session, team: call.team, method: call.method, params: call.params)
            } catch WebKitPoCError.pageBlocked where session.prefersIdle {
                try await session.useFullClient()
                reply = try await pagePost(session, team: call.team, method: call.method, params: call.params)
            }
        case .native:
            reply = try await nativePost(session, team: call.team, method: call.method, params: call.params)
        }

        let elapsed = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let body = String(decoding: reply.body, as: UTF8.self)
        // A response can include Slack credentials for some methods. Keep them out of stdout.
        let redacted = body.replacingOccurrences(of: #"\b(?:xox[a-zA-Z]+|xapp)-[A-Za-z0-9_-]+"#,
                                                  with: "[redacted]", options: .regularExpression)
        let response = (try? JSONSerialization.jsonObject(with: Data(redacted.utf8), options: .fragmentsAllowed))
            ?? (redacted.isEmpty ? NSNull() : redacted as Any)
        var output: [String: Any] = [
            "transport": call.transport.rawValue, "status": reply.status, "elapsedMs": elapsed, "response": response,
        ]
        if let retryAfter = reply.retryAfter, retryAfter.isFinite { output["retryAfter"] = retryAfter }
        return try JSONSerialization.data(withJSONObject: output) + Data([0x0A])
    }

    private struct Call {
        enum Transport: String { case page, native }

        let method: String
        let team: String
        let transport: Transport
        let params: [String: String]

        init(_ arguments: ArraySlice<String>) throws {
            var args = arguments.makeIterator()
            guard args.next() == "call", let method = args.next(),
                  method.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                      || (48...57).contains($0) || $0 == 46 || $0 == 95 }),
                  method.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty })
            else { throw WebKitPoCError.usage }

            var team: String?
            var transport = Transport.page
            var params: [String: String] = [:]
            while let option = args.next() {
                guard let value = args.next() else { throw WebKitPoCError.usage }
                switch option {
                case "--team" where !value.isEmpty:
                    team = value
                case "--transport":
                    guard let selected = Transport(rawValue: value) else { throw WebKitPoCError.usage }
                    transport = selected
                case "--param":
                    guard let separator = value.firstIndex(of: "="), separator != value.startIndex else {
                        throw WebKitPoCError.usage
                    }
                    params[String(value[..<separator])] = String(value[value.index(after: separator)...])
                default:
                    throw WebKitPoCError.usage
                }
            }
            guard let team else { throw WebKitPoCError.usage }
            self.method = method
            self.team = team
            self.transport = transport
            self.params = params
        }
    }
}
