/// Resolve a team to its account and workspace identity.
public struct AccountSelection: Sendable {
    public let account: AccountRecord
    public let team: AccountRecord.Team

    public static func resolve(_ team: TeamID?, in accounts: [AccountRecord]) throws -> AccountSelection {
        if let team {
            for account in accounts {
                guard let workspace = account.teams.first(where: { $0.id == team }) else { continue }
                guard account.state == .active else { throw RemoteError.accountSignedOut(team: workspace.name) }
                return Self(account: account, team: workspace)
            }
            throw RemoteError.noAccount(team: team)
        }

        let available = accounts.filter { $0.state == .active }.flatMap { account in
            account.teams.map { Self(account: account, team: $0) }
        }
        guard let first = available.first else { throw RemoteError.noAccount(team: nil) }
        guard available.count == 1 else {
            throw RemoteError.teamRequired(teams: available.map(\.team.id).sorted { $0.rawValue < $1.rawValue })
        }
        return first
    }
}
