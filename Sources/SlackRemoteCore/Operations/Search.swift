/// Searches Slack for messages or files and verifies requested workspace filters.
public struct SearchRequest: RemoteOperation, Equatable {
    public enum Kind: String, Codable, Sendable { case messages, files }
    public enum Sort: String, Codable, Sendable { case score, timestamp }

    private struct ConversationInfo: Decodable { let channel: SlackConversation }
    private struct MessagePage: Decodable { let messages: SlackSearchPage<SlackSearchMatch> }
    private struct FilePage: Decodable { let files: SlackSearchPage<SlackFile> }

    public let query: String
    public let type: Kind
    public let team: TeamID?
    public let channel: ConversationID?
    public let fromMe: Bool
    public let hasLink: Bool
    public let threadsOnly: Bool
    public let sort: Sort
    public let limit: Int
    public let allowPartial: Bool

    public init(query: String, type: Kind = .messages, team: TeamID? = nil, channel: ConversationID? = nil,
                fromMe: Bool = false, hasLink: Bool = false, threadsOnly: Bool = false, sort: Sort = .score,
                limit: Int = 50, allowPartial: Bool = false) {
        self.query = query
        self.type = type
        self.team = team
        self.channel = channel
        self.fromMe = fromMe
        self.hasLink = hasLink
        self.threadsOnly = threadsOnly
        self.sort = sort
        self.limit = limit
        self.allowPartial = allowPartial
    }

    public func run(in context: OperationContext) async throws -> SearchResult {
        let api = try await context.api(team)
        let query = try await expandedQuery(using: api)
        let params = ["query": query, "sort": sort.rawValue, "sort_dir": "desc", "highlight": "false"]
        let directory = await context.users(api.team)
        let result: SearchResult
        switch type {
        case .messages:
            let page = try await collect(params: params, context: context, fetch: { params in
                try await api.call("search.messages", params, as: MessagePage.self).messages
            }, accept: { match in
                (channel == nil || match.channel.id == channel) && (!fromMe || match.user == api.user)
            })
            let names = try await directory.names(for: Set(page.items.compactMap(\.user)), using: api)
            result = SearchResult(team: api.team, type: type, query: query, total: page.total,
                                  complete: page.complete, stopReason: page.stopReason, pages: page.pages,
                                  results: page.items.map { .message(.init($0, names: names)) })
        case .files:
            let page = try await collect(params: params, context: context, fetch: { params in
                try await api.call("search.files", params, as: FilePage.self).files
            }, accept: { match in
                (channel.map { match.isIn($0) } ?? true) && (!fromMe || match.user == api.user)
            })
            let names = try await directory.names(for: Set(page.items.compactMap(\.user)), using: api)
            result = SearchResult(team: api.team, type: type, query: query, total: page.total,
                                  complete: page.complete, stopReason: page.stopReason, pages: page.pages,
                                  results: page.items.map { .file(.init($0, names: names)) })
        }
        return try result.returningPartial(allowPartial)
    }

    /// Translate the CLI filters into Slack query modifiers.
    private func expandedQuery(using api: SlackAPI) async throws -> String {
        var terms = [query]
        if let channel {
            let info = try await api.call("conversations.info", ["channel": channel.rawValue],
                                          as: ConversationInfo.self).channel
            if info.isMpim == true { throw RemoteError.unsupportedDestination }
            if info.isIm == true {
                guard let user = info.user else { throw RemoteError.unsupportedDestination }
                let response = try await api.call("users.info", ["user": user.rawValue], as: SlackUserInfo.self)
                guard let handle = response.user.name, !handle.isEmpty else { throw RemoteError.unsupportedDestination }
                terms.append("in:@\(handle)")
            } else {
                guard let name = info.name, !name.isEmpty else { throw RemoteError.unsupportedDestination }
                terms.append("in:#\(name)")
            }
        }
        if fromMe { terms.append("from:<@\(api.user.rawValue)>") }
        if hasLink { terms.append("has:link") }
        if threadsOnly { terms.append("is:thread") }
        return terms.joined(separator: " ")
    }

    private struct Matches<Match> {
        var items: [Match] = []
        var total = 0
        var pages = 0
        var stopReason: StopReason = .limit
        var complete: Bool { stopReason == .endOfList }
    }

    /// Apply post-filters before counting matches toward the caller's limit.
    private func collect<Match: Decodable>(
        params: [String: String], context: OperationContext,
        fetch: ([String: String]) async throws -> SlackSearchPage<Match>, accept: (Match) -> Bool
    ) async throws -> Matches<Match> {
        var result = Matches<Match>()
        var filtered = 0
        defer { if filtered > 0 { context.warn("filtered_\(filtered)") } }
        var params = params
        // Slack computes the offset from (page - 1) × count, so count must stay fixed between calls.
        params["count"] = String(min(100, limit))
        while result.items.count < limit {
            params["page"] = String(result.pages + 1)
            let page: SlackSearchPage<Match>
            do { page = try await fetch(params) }
            catch RemoteError.timeout {
                result.stopReason = .deadline
                break
            }
            result.pages += 1
            result.total = page.total
            let accepted = page.matches.filter(accept)
            filtered += page.matches.count - accepted.count
            let remaining = limit - result.items.count
            result.items.append(contentsOf: accepted.prefix(remaining))
            if accepted.count > remaining { break }
            if page.paging.page >= page.paging.pages {
                result.stopReason = .endOfList
                break
            }
        }
        return result
    }
}

/// Slack's match count and the message or file rows returned by this search.
public struct SearchResult: ListResult {
    public enum Match: Encodable, Equatable, Sendable {
        case message(MessageMatch)
        case file(FileMatch)

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .message(let match): try match.encode(to: encoder)
            case .file(let match): try match.encode(to: encoder)
            }
        }
    }

    public struct MessageMatch: Encodable, Equatable, Sendable {
        public let ts: String
        public let conversation: ConversationID
        public let conversationName: String?
        public let user: UserID?
        public let userName: String?
        public let text: String
        public let permalink: String

        init(_ match: SlackSearchMatch, names: [UserID: String]) {
            ts = match.ts
            conversation = match.channel.id
            conversationName = match.channel.name
            user = match.user
            userName = match.user.flatMap { names[$0] }
            text = match.text
            permalink = match.permalink
        }
    }

    public struct FileMatch: Encodable, Equatable, Sendable {
        public let id: String
        public let name: String?
        public let title: String?
        public let mimetype: String?
        public let size: Int?
        public let user: UserID?
        public let userName: String?
        public let created: Int?
        public let permalink: String?

        init(_ match: SlackFile, names: [UserID: String]) {
            id = match.id
            name = match.name
            title = match.title
            mimetype = match.mimetype
            size = match.size
            user = match.user
            userName = match.user.flatMap { names[$0] }
            created = match.created
            permalink = match.permalink
        }
    }

    public let team: TeamID
    public let type: SearchRequest.Kind
    public let query: String
    public let total: Int
    public let complete: Bool
    public let stopReason: StopReason
    public let pages: Int
    public let results: [Match]
}
