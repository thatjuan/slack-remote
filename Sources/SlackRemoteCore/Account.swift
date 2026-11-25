import Foundation

public struct Account: Codable, Equatable {
    public let team: TeamID
    public let user: UserID
    public let selfDM: ConversationID?

    public enum Access { case read, write, dryRunWrite }

    public enum Verification: String, Encodable {
        case verified
        case unconfigured
        case unverified
    }

    public init(team: TeamID, user: UserID, selfDM: ConversationID?) {
        self.team = team
        self.user = user
        self.selfDM = selfDM
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(team, forKey: .team)
        try values.encode(user, forKey: .user)
        try values.encode(selfDM, forKey: .selfDM)
    }

    public static func identify(in tree: SlackTree, deadline: Date) throws -> Account {
        try tree.refresh()
        try Overlays.requireUnblocked(in: tree)
        let client = try SlackWindow.currentWindow(in: tree)
        guard let team = client.location.team else { throw RemoteError.slackNotReady }
        let selfDM = try sidebarSelfDM(in: client.window)
        let button = try client.window.one(Locators.searchButton)
        let user: UserID = try Overlays.withModal(in: tree, deadline: deadline, opening: {
            guard Date() < deadline else { throw RemoteError.timeout }
            try button.perform(.press)
        }) { modal in
            // Clear a restored search field even if the quick filter could not be read.
            let result = Result {
                let filter = try modal.one(Locators.selfFilter)
                let raw = filter.domID?.dropFirst(Locators.selfFilterPrefix.count) ?? ""
                guard let id = UserID(String(raw)) else { throw RemoteError.accountUnverified }
                return id
            }
            let clear = modal.all(Locators.searchClear)
            guard clear.count <= 1 else {
                throw RemoteError.uiDrift(locator: Locators.searchClear.name, found: clear.count)
            }
            if let clearButton = clear.first { try clearButton.perform(.press) }
            return try result.get()
        }
        guard try SlackWindow.currentWindow(in: tree).location == client.location else {
            throw RemoteError.accountUnverified
        }
        return Account(team: team, user: user, selfDM: selfDM)
    }

    /// Dry runs use the sidebar only. An absent row leaves the account unverified in the plan.
    public static func verify(team: TeamID, in tree: SlackTree, config: Config?, access: Access,
                              deadline: Date, window: (any UINode)? = nil,
                              warn: (String) -> Void = { _ in }) throws -> Verification {
        guard let config else {
            if access != .read { warn("no_account_configured") }
            return .unconfigured
        }
        guard let expected = config.accounts.first(where: { $0.team == team }) else {
            if access != .read { throw RemoteError.accountUnverified }
            warn("account_unverified")
            return .unverified
        }

        let client = try SlackWindow.currentWindow(in: tree)
        let sidebarWindow = window ?? (client.location.team == team ? client.window : nil)
        if let sidebarWindow, let selfDM = try sidebarSelfDM(in: sidebarWindow) {
            guard expected.selfDM == selfDM else { throw RemoteError.accountMismatch }
            return .verified
        }
        if access == .write {
            guard client.location.team == team else { throw RemoteError.accountUnverified }
            let observed = try identify(in: tree, deadline: deadline)
            guard observed.team == team, observed.user == expected.user else { throw RemoteError.accountMismatch }
            return .verified
        }
        warn("account_unverified")
        return .unverified
    }

    public static func sidebarSelfDM(in window: any UINode) throws -> ConversationID? {
        let rows = window.all(Locators.sidebarRow).filter { row in
            row.domClasses.contains(Locators.selfDM)
                || row.descendants().contains { $0.domClasses.contains(Locators.selfDM) }
        }
        if rows.isEmpty { return nil }
        guard rows.count == 1, let raw = rows.first?.domID,
              let id = ConversationID(raw), id.kind == .directMessage else {
            throw RemoteError.accountUnverified
        }
        return id
    }
}
