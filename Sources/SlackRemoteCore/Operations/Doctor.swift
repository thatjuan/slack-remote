import Foundation

/// Check the helper and verify each recorded workspace's Slack identity.
public struct DoctorRequest: RemoteOperation, Equatable {
    public struct Output: Encodable, Sendable {
        public struct Check: Encodable, Sendable {
            public let name: String
            public let ok: Bool
            public let detail: String
        }
        public let checks: [Check]
    }

    public init() {}

    public func run(in context: OperationContext) async throws -> Output {
        let accounts = await context.accounts()
        let active = accounts.filter { $0.state == .active }
        let accountCount = active.count
        let teamCount = active.reduce(0) { $0 + $1.teams.count }
        var checks: [Output.Check] = [
            .init(name: "helper", ok: true, detail: "SlackRemote.app \(context.helperVersion)"),
            .init(name: "accounts", ok: !active.isEmpty, detail: active.isEmpty
                  ? "no accounts: choose Add Slack Account in the SlackRemote menu"
                  : "\(accountCount) \(accountCount == 1 ? "account" : "accounts"), \(teamCount) \(teamCount == 1 ? "workspace" : "workspaces")"),
        ]
        var firstError: RemoteError? = active.isEmpty ? .noAccount(team: nil) : nil
        let clock = ContinuousClock()
        for account in accounts {
            for team in account.teams {
                let name = "session:\(team.id.rawValue)"
                let started = clock.now
                do {
                    let api = try await context.api(team.id)
                    _ = try await api.verifiedIdentity()
                    let elapsed = started.duration(to: clock.now).components
                    let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
                    checks.append(.init(name: name, ok: true,
                                        detail: "\(team.name) as \(team.userName), \(milliseconds) ms"))
                } catch {
                    let failure = error as? RemoteError ?? .internalError(operation: "doctor")
                    if case .interrupted = failure { throw failure }
                    if firstError == nil { firstError = failure }
                    checks.append(.init(name: name, ok: false, detail: failure.code))
                }
            }
        }
        let result = Output(checks: checks)
        if let firstError { throw OperationFailure(error: firstError, result: result) }
        return result
    }
}
