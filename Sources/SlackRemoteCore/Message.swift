/// A stored Slack message with the fields needed to read it outside Slack.
public struct Message: Encodable, Equatable, Sendable {
    public let ts: String
    public let user: String?
    public let userName: String?
    public let botId: String?
    public let subtype: String?
    public let text: String
    public let threadTs: String?
    public let replyCount: Int?
    public let edited: Bool
    public let files: [FileRef]
    public let reactions: [Reaction]

    init(_ message: SlackMessage, names: [UserID: String], viewer: UserID) {
        ts = message.ts
        user = message.user?.rawValue
        let name = message.user.flatMap { names[$0] }
        let botName = message.botProfile?.name ?? message.username
        userName = message.botId != nil || message.subtype == "bot_message" ? botName ?? name : name ?? botName
        botId = message.botId
        subtype = message.subtype
        text = message.text
        threadTs = message.threadTs ?? ((message.replyCount ?? 0) > 0 ? message.ts : nil)
        replyCount = threadTs == ts ? message.replyCount : nil
        edited = message.edited != nil
        files = (message.files ?? []).map(FileRef.init)
        reactions = (message.reactions ?? []).map { Reaction($0, viewer: viewer) }
    }

    private enum CodingKeys: String, CodingKey {
        case ts, user, userName, botId, subtype, text, threadTs, replyCount, edited, files, reactions
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(ts, forKey: .ts)
        try fields.encode(user, forKey: .user)
        try fields.encode(userName, forKey: .userName)
        try fields.encode(botId, forKey: .botId)
        try fields.encode(subtype, forKey: .subtype)
        try fields.encode(text, forKey: .text)
        try fields.encode(threadTs, forKey: .threadTs)
        try fields.encode(replyCount, forKey: .replyCount)
        try fields.encode(edited, forKey: .edited)
        try fields.encode(files, forKey: .files)
        try fields.encode(reactions, forKey: .reactions)
    }
}

/// Slack's metadata for a file attached to a message.
public struct FileRef: Encodable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let title: String?
    public let mimetype: String?
    public let size: Int?
    public let permalink: String?

    init(_ file: SlackFile) {
        id = file.id
        name = file.name
        title = file.title
        mimetype = file.mimetype
        size = file.size
        permalink = file.permalink
    }
}

/// A Slack reaction and whether the signed-in user appears among its reactors.
public struct Reaction: Encodable, Equatable, Sendable {
    public let name: String
    public let count: Int
    public let reacted: Bool

    init(_ reaction: SlackMessage.Reaction, viewer: UserID) {
        name = reaction.name
        count = reaction.count
        reacted = reaction.users?.contains(viewer) == true
    }
}
