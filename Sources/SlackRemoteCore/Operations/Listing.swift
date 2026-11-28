/// A list that can include its collected rows in a deadline error.
protocol ListResult: Encodable, Sendable {
    var stopReason: StopReason { get }
}

extension ListResult {
    func returningPartial(_ allowed: Bool) throws -> Self {
        if stopReason == .deadline && !allowed {
            throw OperationFailure(error: .partialResult, result: self)
        }
        return self
    }
}

/// Lists workspace memberships or the public conversation directory.
public struct ChannelsRequest: RemoteOperation, Equatable {
    public enum Source: String, Codable, Sendable { case member, all }

    private struct Page: CursorPage {
        let channels: [SlackConversation]
        let responseMetadata: SlackCursor?
        var items: [SlackConversation] { channels }
        var nextCursor: String? { responseMetadata?.nextCursor }
    }

    public let team: TeamID?
    public let source: Source
    public let includeArchived: Bool
    public let limit: Int
    public let allowPartial: Bool

    public init(team: TeamID? = nil, source: Source = .member, includeArchived: Bool = false,
                limit: Int = 500, allowPartial: Bool = false) {
        self.team = team
        self.source = source
        self.includeArchived = includeArchived
        self.limit = limit
        self.allowPartial = allowPartial
    }

    public func run(in context: OperationContext) async throws -> ChannelsResult {
        let api = try await context.api(team)
        let params = [
            "types": source == .member ? "public_channel,private_channel,mpim,im" : "public_channel",
            "exclude_archived": String(!includeArchived),
        ]
        let page = try await api.paginate(source == .member ? "users.conversations" : "conversations.list",
                                          params, limit: limit, as: Page.self)
        let directUsers = Set(page.items.filter { $0.isIm == true }.compactMap(\.user))
        let directory = await context.users(api.team)
        var names = try await directory.names(for: directUsers.subtracting([api.user]), using: api)
        if directUsers.contains(api.user) {
            let account = try AccountSelection.resolve(api.team, in: await context.accounts())
            names[api.user] = account.team.userName
        }
        let rows = page.items.map { ChannelsResult.Row($0, viewer: api.user, names: names) }
        return try ChannelsResult(team: api.team, source: source, complete: page.complete,
                                  stopReason: page.stopReason, pages: page.pages, channels: rows)
            .returningPartial(allowPartial)
    }
}

/// The conversations collected from the chosen workspace directory.
public struct ChannelsResult: ListResult {
    public struct Row: Encodable, Equatable, Sendable {
        public enum Kind: String, Encodable, Sendable {
            case channel
            case privateChannel = "private_channel"
            case dm
            case groupDM = "group_dm"
            case selfDM = "self_dm"
        }

        public let id: ConversationID
        public let name: String?
        public let kind: Kind
        public let archived: Bool
        public let user: UserID?

        init(_ channel: SlackConversation, viewer: UserID, names: [UserID: String]) {
            id = channel.id
            if channel.isIm == true {
                kind = channel.user == viewer ? .selfDM : .dm
                name = channel.user.flatMap { names[$0] }
                user = kind == .dm ? channel.user : nil
            } else {
                if channel.isMpim == true { kind = .groupDM }
                else if channel.isPrivate == true { kind = .privateChannel }
                else { kind = .channel }
                name = channel.name
                user = nil
            }
            archived = channel.isArchived == true
        }
    }

    public let team: TeamID
    public let source: ChannelsRequest.Source
    public let complete: Bool
    public let stopReason: StopReason
    public let pages: Int
    public let channels: [Row]
}

/// Lists users in a Slack channel, DM or group DM.
public struct MembersRequest: RemoteOperation, Equatable {
    private struct Page: CursorPage {
        let members: [UserID]
        let responseMetadata: SlackCursor?
        var items: [UserID] { members }
        var nextCursor: String? { responseMetadata?.nextCursor }
    }

    public let destination: Destination
    public let limit: Int
    public let allowPartial: Bool

    public init(destination: Destination, limit: Int = 500, allowPartial: Bool = false) {
        self.destination = destination
        self.limit = limit
        self.allowPartial = allowPartial
    }

    public func run(in context: OperationContext) async throws -> MembersResult {
        let api = try await context.api(destination.team)
        let page = try await api.paginate("conversations.members", ["channel": destination.conversation.rawValue],
                                          limit: limit, as: Page.self)
        let directory = await context.users(api.team)
        let names = try await directory.names(for: Set(page.items), using: api)
        let members = page.items.map { MembersResult.Row(user: $0, name: names[$0]) }
        return try MembersResult(team: api.team, conversation: destination.conversation,
                                 complete: page.complete, stopReason: page.stopReason, pages: page.pages,
                                 members: members).returningPartial(allowPartial)
    }
}

/// Workspace and conversation IDs accompany the collected member rows.
public struct MembersResult: ListResult {
    public struct Row: Encodable, Equatable, Sendable {
        public let user: UserID
        public let name: String?
    }

    public let team: TeamID
    public let conversation: ConversationID
    public let complete: Bool
    public let stopReason: StopReason
    public let pages: Int
    public let members: [Row]
}

/// Lists workspace users and populates the name cache from every Slack page.
public struct PeopleRequest: RemoteOperation, Equatable {
    private struct Page: CursorPage {
        let members: [SlackUser]
        let responseMetadata: SlackCursor?
        var items: [SlackUser] { members }
        var nextCursor: String? { responseMetadata?.nextCursor }
    }

    public let team: TeamID?
    public let includeBots: Bool
    public let includeDeleted: Bool
    public let limit: Int
    public let allowPartial: Bool

    public init(team: TeamID? = nil, includeBots: Bool = false, includeDeleted: Bool = false,
                limit: Int = 500, allowPartial: Bool = false) {
        self.team = team
        self.includeBots = includeBots
        self.includeDeleted = includeDeleted
        self.limit = limit
        self.allowPartial = allowPartial
    }

    public func run(in context: OperationContext) async throws -> PeopleResult {
        let api = try await context.api(team)
        let directory = await context.users(api.team)
        let page = try await api.paginate("users.list", [:], limit: limit, as: Page.self) { users, _ in
            await directory.seed(users)
            return users.filter { (includeBots || !$0.bot) && (includeDeleted || $0.deleted != true) }
        }
        return try PeopleResult(team: api.team, complete: page.complete, stopReason: page.stopReason,
                                pages: page.pages, people: page.items.map(PeopleResult.Row.init))
            .returningPartial(allowPartial)
    }
}

/// The user records that passed the directory filters.
public struct PeopleResult: ListResult {
    public struct Row: Encodable, Equatable, Sendable {
        public let user: UserID
        public let name: String?
        public let realName: String?
        public let displayName: String?
        public let isBot: Bool
        public let deleted: Bool

        init(_ user: SlackUser) {
            self.user = user.id
            name = user.name
            realName = user.profile?.realName ?? user.realName
            displayName = user.profile?.displayName
            isBot = user.bot
            deleted = user.deleted == true
        }
    }

    public let team: TeamID
    public let complete: Bool
    public let stopReason: StopReason
    public let pages: Int
    public let people: [Row]
}
