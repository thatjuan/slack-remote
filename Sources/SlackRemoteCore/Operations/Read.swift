import Foundation

/// Reads the newest conversation messages or the oldest messages in a thread.
public struct ReadRequest: RemoteOperation, Equatable {
    public let destination: Destination
    public let thread: String?
    public let since: String?
    public let until: String?
    public let limit: Int
    public let allowPartial: Bool

    public init(destination: Destination, thread: String? = nil, since: String? = nil, until: String? = nil,
                limit: Int = 50, allowPartial: Bool = false) {
        self.destination = destination
        self.thread = thread
        self.since = since
        self.until = until
        self.limit = limit
        self.allowPartial = allowPartial
    }

    private struct Page: CursorPage {
        let messages: [SlackMessage]
        let responseMetadata: SlackCursor?
        var items: [SlackMessage] { messages }
        var nextCursor: String? { responseMetadata?.nextCursor }
    }

    public func run(in context: OperationContext) async throws -> ReadResult {
        let api = try await context.api(destination.team)
        var params = ["channel": destination.conversation.rawValue]
        params["ts"] = thread
        params["oldest"] = since
        params["latest"] = until

        let page = try await api.paginate(thread == nil ? "conversations.history" : "conversations.replies",
                                          params, limit: limit, as: Page.self) { messages, number in
            if number == 1, let thread {
                guard let parent = messages.first, parent.ts == thread, (parent.threadTs ?? thread) == thread else {
                    throw RemoteError.messageNotFound
                }
            }
            return messages
        }

        let directory = await context.users(api.team)
        let names = try await directory.names(for: Set(page.items.compactMap(\.user)), using: api)
        let messages = (thread == nil ? Array(page.items.reversed()) : page.items).map {
            Message($0, names: names, viewer: api.user)
        }
        let stopReason: StopReason = page.complete && since != nil ? .boundary : page.stopReason
        let result = ReadResult(team: api.team, conversation: destination.conversation, thread: thread,
                                complete: page.complete, stopReason: stopReason, pages: page.pages,
                                oldestTs: messages.first?.ts, newestTs: messages.last?.ts,
                                readAt: Date().ISO8601Format(), messages: messages)
        return try result.returningPartial(allowPartial)
    }
}

/// Messages in chronological order and the bounds covered by the read.
public struct ReadResult: ListResult {
    public let team: TeamID
    public let conversation: ConversationID
    public let thread: String?
    public let complete: Bool
    public let stopReason: StopReason
    public let pages: Int
    public let oldestTs: String?
    public let newestTs: String?
    public let readAt: String
    public let messages: [Message]

    private enum CodingKeys: String, CodingKey {
        case team, conversation, thread, complete, stopReason, pages, oldestTs, newestTs, readAt, messages
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(team, forKey: .team)
        try fields.encode(conversation, forKey: .conversation)
        try fields.encode(thread, forKey: .thread)
        try fields.encode(complete, forKey: .complete)
        try fields.encode(stopReason, forKey: .stopReason)
        try fields.encode(pages, forKey: .pages)
        try fields.encode(oldestTs, forKey: .oldestTs)
        try fields.encode(newestTs, forKey: .newestTs)
        try fields.encode(readAt, forKey: .readAt)
        try fields.encode(messages, forKey: .messages)
    }
}
