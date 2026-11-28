/// Slack's user record. People listings also use these records to fill the name cache.
public struct SlackUser: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        let displayName: String?
        let realName: String?
    }

    let id: UserID
    let name: String?
    let realName: String?
    let profile: Profile?
    let isBot: Bool?
    let isAppUser: Bool?
    let deleted: Bool?

    var displayLabel: String? {
        [profile?.displayName, profile?.realName, name].compactMap { $0 }.first { !$0.isEmpty }
    }

    var bot: Bool { isBot == true || isAppUser == true || id.rawValue == "USLACKBOT" }
}

/// The conversation fields shared by Slack's info and directory methods.
struct SlackConversation: Decodable, Sendable {
    let id: ConversationID
    let name: String?
    private let rawUser: String?
    let isIm: Bool?
    let isMpim: Bool?
    let isPrivate: Bool?
    let isArchived: Bool?

    // Slack may send an empty user field on a direct conversation.
    var user: UserID? { rawUser.flatMap { UserID($0) } }

    private enum CodingKeys: String, CodingKey {
        case id, name, isIm, isMpim, isPrivate, isArchived
        case rawUser = "user"
    }
}

/// Slack's file record, used in messages and file search.
struct SlackFile: Decodable, Sendable {
    let id: String
    let name: String?
    let title: String?
    let mimetype: String?
    let size: Int?
    let permalink: String?
    let user: UserID?
    let created: Int?
    let channel: SlackConversation?
    let channels: [ConversationID]?
    let groups: [ConversationID]?
    let ims: [ConversationID]?

    func isIn(_ conversation: ConversationID) -> Bool {
        if let channel { return channel.id == conversation }
        return [channels, groups, ims].contains { $0?.contains(conversation) == true }
    }
}

/// The message and reaction fields returned by history and replies.
struct SlackMessage: Decodable, Sendable {
    struct BotProfile: Decodable, Sendable {
        let name: String?
    }

    struct Edited: Decodable, Sendable {}

    struct Reaction: Decodable, Sendable {
        let name: String
        let count: Int
        let users: [UserID]?
    }

    let ts: String
    let user: UserID?
    let botId: String?
    let botProfile: BotProfile?
    let username: String?
    let subtype: String?
    let text: String
    let threadTs: String?
    let replyCount: Int?
    let edited: Edited?
    let files: [SlackFile]?
    let reactions: [Reaction]?
}

struct SlackSearchMatch: Decodable, Sendable {
    let ts: String
    let channel: SlackConversation
    let user: UserID?
    let text: String
    let permalink: String
}

struct SlackSearchPage<Match: Decodable>: Decodable {
    struct Paging: Decodable {
        let page: Int
        let pages: Int
    }

    let total: Int
    let paging: Paging
    let matches: [Match]
}

struct SlackCursor: Decodable {
    let nextCursor: String?
}

struct SlackUserInfo: Decodable {
    let user: SlackUser
}
