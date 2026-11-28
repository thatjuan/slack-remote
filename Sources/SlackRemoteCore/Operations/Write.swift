import Foundation

/// The CLI's destination selection, resolved against the helper's config.
public enum WriteTarget: Codable, Equatable, Sendable {
    case named(String)
    case explicit(Destination)

    func resolve(using config: Config?) throws -> Destination {
        switch self {
        case .named(let name):
            guard let destination = config?.destinations[name] else { throw RemoteError.unsupportedDestination }
            return destination
        case .explicit(let destination):
            return destination
        }
    }
}

/// A write either returns a plan or the receipt from Slack.
public enum WriteResult<Receipt: Encodable & Sendable>: Encodable, Sendable {
    case dryRun(WritePreview)
    case completed(Receipt)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .dryRun(let preview): try preview.encode(to: encoder)
        case .completed(let receipt): try receipt.encode(to: encoder)
        }
    }
}

/// A plan for a destination and account verified by preflight.
public struct WritePreview: Encodable, Sendable {
    public struct Account: Encodable, Sendable {
        public let user: UserID
        public let userName: String
    }

    public let dryRun = true
    public let team: TeamID
    public let conversation: ConversationID
    public let conversationName: String?
    public let account: Account
    public let plan: [String]

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(dryRun, forKey: .dryRun)
        try fields.encode(team, forKey: .team)
        try fields.encode(conversation, forKey: .conversation)
        try fields.encode(conversationName, forKey: .conversationName)
        try fields.encode(account, forKey: .account)
        try fields.encode(plan, forKey: .plan)
    }

    private enum CodingKeys: String, CodingKey {
        case dryRun, team, conversation, conversationName, account, plan
    }
}

/// Checks the account and write allowlist before input validation or Slack requests.
struct WritePreflight {
    let destination: Destination
    let api: SlackAPI

    private struct ConversationInfo: Decodable {
        struct Channel: Decodable {
            let name: String?
            let isChannel: Bool?
            let isGroup: Bool?
            let isIm: Bool?
            let isMpim: Bool?
            let isMember: Bool?
            let isArchived: Bool?
        }

        let channel: Channel
    }

    private struct ThreadInfo: Decodable {
        struct Message: Decodable {
            let ts: String
            let threadTs: String?
        }

        let messages: [Message]
    }

    init(_ target: WriteTarget, in context: OperationContext) async throws {
        destination = try target.resolve(using: context.config)
        api = try await context.api(destination.team)
        try context.config?.requireWriteAllowed(to: destination)
    }

    /// Verifies the conversation and, when supplied, that the timestamp is a thread root.
    func verifyConversation(thread: String? = nil) async throws -> String? {
        let params = ["channel": destination.conversation.rawValue]
        let info = try await api.call("conversations.info", params, as: ConversationInfo.self)
        if info.channel.isArchived == true {
            throw RemoteError.destinationUnavailable(reason: .archived)
        }
        let isChannel = info.channel.isChannel == true || info.channel.isGroup == true ||
            destination.conversation.kind == .channel
        if isChannel, info.channel.isIm != true, info.channel.isMpim != true, info.channel.isMember == false {
            throw RemoteError.destinationUnavailable(reason: .notAMember)
        }
        if let thread {
            var params = params
            params["ts"] = thread
            params["limit"] = "1"
            let info = try await api.call("conversations.replies", params, as: ThreadInfo.self)
            guard let root = info.messages.first, root.ts == thread, root.threadTs == nil || root.threadTs == thread else {
                throw RemoteError.messageNotFound
            }
        }
        return info.channel.name
    }

    /// Uses the same identity as the team-bound client for the dry-run plan.
    func preview(_ plan: String, conversationName: String?, in context: OperationContext) async throws -> WritePreview {
        let records = await context.accounts()
        let selection = try AccountSelection.resolve(api.team, in: records)
        guard api.user == selection.team.user else { throw RemoteError.accountMismatch }
        return WritePreview(team: api.team, conversation: destination.conversation, conversationName: conversationName,
                            account: .init(user: api.user, userName: selection.team.userName), plan: [plan])
    }
}

/// Posts to the conversation's main timeline.
public struct SendRequest: RemoteOperation, Equatable {
    public let target: WriteTarget
    public let text: String
    public let allowBroadcast: Bool
    public let dryRun: Bool

    public init(target: WriteTarget, text: String, allowBroadcast: Bool = false, dryRun: Bool = false) {
        self.target = target
        self.text = text
        self.allowBroadcast = allowBroadcast
        self.dryRun = dryRun
    }

    public func run(in context: OperationContext) async throws -> WriteResult<MessageReceipt> {
        try await postMessage(target: target, text: text, allowBroadcast: allowBroadcast, dryRun: dryRun, in: context)
    }
}

/// Posts to a verified thread and optionally broadcasts the reply to its conversation.
public struct ReplyRequest: RemoteOperation, Equatable {
    public let target: WriteTarget
    public let thread: String
    public let text: String
    public let alsoSendToChannel: Bool
    public let allowBroadcast: Bool
    public let dryRun: Bool

    public init(target: WriteTarget, thread: String, text: String, alsoSendToChannel: Bool = false,
                allowBroadcast: Bool = false, dryRun: Bool = false) {
        self.target = target
        self.thread = thread
        self.text = text
        self.alsoSendToChannel = alsoSendToChannel
        self.allowBroadcast = allowBroadcast
        self.dryRun = dryRun
    }

    public func run(in context: OperationContext) async throws -> WriteResult<MessageReceipt> {
        try await postMessage(target: target, text: text, allowBroadcast: allowBroadcast, dryRun: dryRun,
                              thread: (thread, alsoSendToChannel), in: context)
    }
}

/// The timestamp Slack returned for a posted message.
public struct MessageReceipt: Encodable, Sendable {
    public let team: TeamID
    public let conversation: ConversationID
    public let thread: String?
    public let sent = true
    public let ts: String
}

private struct PostedMessage: Decodable {
    let ts: String
}

/// Shares the text rules and posting behavior for messages and replies.
private func postMessage(target: WriteTarget, text: String, allowBroadcast: Bool, dryRun: Bool,
                         thread: (ts: String, broadcast: Bool)? = nil, in context: OperationContext)
    async throws -> WriteResult<MessageReceipt> {
    let preflight = try await WritePreflight(target, in: context)
    try MessageText.validate(text, allowBroadcast: allowBroadcast)
    if let thread, !SlackTimestamp.isValid(thread.ts) { throw RemoteError.messageNotFound }
    let name = try await preflight.verifyConversation(thread: thread?.ts)
    if dryRun {
        let plan = thread.map {
            "post reply in thread \($0.ts) (\(text.count) characters)" + ($0.broadcast ? ", also to channel" : "")
        } ?? "post message (\(text.count) characters)"
        return .dryRun(try await preflight.preview(plan, conversationName: name, in: context))
    }
    let destination = preflight.destination
    var params = ["channel": destination.conversation.rawValue, "text": text]
    if let thread {
        params["thread_ts"] = thread.ts
        params["reply_broadcast"] = String(thread.broadcast)
    }
    let response: PostedMessage
    do { response = try await preflight.api.call("chat.postMessage", params) }
    catch RemoteError.networkUnavailable { throw RemoteError.sendUnconfirmed }
    return .completed(.init(team: destination.team, conversation: destination.conversation,
                            thread: thread?.ts, ts: response.ts))
}

/// Adds an emoji by message timestamp, including messages within threads.
public struct ReactRequest: RemoteOperation, Equatable {
    public struct Receipt: Encodable, Sendable {
        public let team: TeamID
        public let conversation: ConversationID
        public let ts: String
        public let emoji: String
        public let reacted = true
        public let alreadyReacted: Bool
    }

    public let target: WriteTarget
    public let ts: String
    public let emoji: String
    public let dryRun: Bool

    public init(target: WriteTarget, ts: String, emoji: String, dryRun: Bool = false) {
        self.target = target
        self.ts = ts
        self.emoji = emoji
        self.dryRun = dryRun
    }

    public func run(in context: OperationContext) async throws -> WriteResult<Receipt> {
        let preflight = try await WritePreflight(target, in: context)
        guard MessageText.isEmojiName(emoji) else { throw RemoteError.unsafeText(reason: "invalid_emoji_name") }
        guard SlackTimestamp.isValid(ts) else { throw RemoteError.messageNotFound }
        let name = try await preflight.verifyConversation()
        if dryRun {
            return .dryRun(try await preflight.preview("add reaction :\(emoji): to \(ts)", conversationName: name, in: context))
        }
        let destination = preflight.destination
        let params = ["channel": destination.conversation.rawValue, "timestamp": ts, "name": emoji]
        let alreadyReacted: Bool
        do {
            _ = try await preflight.api.call("reactions.add", params, as: SlackAcknowledgement.self)
            alreadyReacted = false
        } catch RemoteError.slackAPI(_, "already_reacted") {
            alreadyReacted = true
        } catch RemoteError.slackAPI(_, "invalid_name") {
            throw RemoteError.unsafeText(reason: "invalid_emoji_name")
        } catch RemoteError.networkUnavailable {
            throw RemoteError.reactionUnconfirmed
        }
        return .completed(.init(team: destination.team, conversation: destination.conversation, ts: ts, emoji: emoji,
                                alreadyReacted: alreadyReacted))
    }
}

/// A successful Slack response whose body carries no data used by the command.
struct SlackAcknowledgement: Decodable {}
