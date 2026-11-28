import Foundation

/// Identifies both the account record and its persistent WebKit profile.
public struct AccountID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// The account's workspace identities. Credentials live in its WebKit profile.
public struct AccountRecord: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case active, signedOut }

    public struct Team: Codable, Equatable, Sendable {
        public let id: TeamID
        public var name: String
        public var url: URL
        public var user: UserID
        public var userName: String

        public init(id: TeamID, name: String, url: URL, user: UserID, userName: String) {
            self.id = id
            self.name = name
            self.url = url
            self.user = user
            self.userName = userName
        }
    }

    public let id: AccountID
    public var teams: [Team]
    public var state: State
    public let addedAt: Date

    public init(id: AccountID, teams: [Team], state: State, addedAt: Date) {
        self.id = id
        self.teams = teams
        self.state = state
        self.addedAt = addedAt
    }
}

/// The on-disk accounts file, with teams stored in the order they were added.
public struct AccountFile: Codable, Equatable, Sendable {
    public var version = 1
    public var accounts: [AccountRecord]

    public init(accounts: [AccountRecord] = []) {
        self.accounts = accounts
    }
}
