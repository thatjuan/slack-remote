/// Return the helper's account inventory without opening any Slack views.
public struct AccountsListRequest: RemoteOperation, Equatable {
    public struct Output: Encodable, Sendable {
        public struct Account: Encodable, Sendable {
            public let id: String
            public let state: AccountRecord.State
            public let teams: [AccountRecord.Team]
        }
        public let accounts: [Account]
    }

    public init() {}

    public func run(in context: OperationContext) async throws -> Output {
        let accounts = await context.accounts()
        return Output(accounts: accounts.map {
            .init(id: $0.id.rawValue.uuidString, state: $0.state, teams: $0.teams)
        })
    }
}

/// Open a sign-in window and optionally wait for the recorded teams.
public struct AccountsAddRequest: RemoteOperation, Equatable {
    public struct Output: Encodable, Sendable {
        public let opened: Bool
        public let added: [TeamID]?
    }

    public let wait: Bool

    public init(wait: Bool = false) {
        self.wait = wait
    }

    public func run(in context: OperationContext) async throws -> Output {
        let added = try await context.ui.add(wait, context.deadline)
        return Output(opened: true, added: added)
    }
}

/// Remove an account by the ID returned by accounts list.
public struct AccountsRemoveRequest: RemoteOperation, Equatable {
    public struct Output: Encodable, Sendable {
        public let removed: Bool
    }

    public let id: AccountID

    public init(id: AccountID) {
        self.id = id
    }

    public func run(in context: OperationContext) async throws -> Output {
        try await context.ui.remove(id)
        return Output(removed: true)
    }
}
