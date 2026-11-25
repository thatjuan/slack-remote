public struct Message: Encodable, Equatable {
    public let ts: String
    public let sender: String?
    public let senderInherited: Bool
    public let text: String
    public let hasAttachments: Bool
    public let reactions: [Reaction]

    private enum CodingKeys: String, CodingKey {
        case ts, sender, senderInherited, text, hasAttachments, reactions
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ts, forKey: .ts)
        try container.encode(sender, forKey: .sender)
        try container.encode(senderInherited, forKey: .senderInherited)
        try container.encode(text, forKey: .text)
        try container.encode(hasAttachments, forKey: .hasAttachments)
        try container.encode(reactions, forKey: .reactions)
    }
}

public struct Reaction: Encodable, Equatable {
    public let label: String
    public let reacted: Bool
}

public enum MessageReader {
    private static let messageID = #/message-list_([0-9]{10}\.[0-9]{6})/#

    public static func read(_ view: VerifiedView, limit: Int?) throws -> (messages: [Message], skippedItems: Int) {
        let list = try view.primaryView.one(Locators.messageList)
        var messages: [Message] = []
        var skippedItems = 0
        var previousSender: String?

        for item in list.children {
            // A gap in the rendered message sequence ends sender inheritance.
            guard Locators.messageItem.matches(item),
                  let match = item.domID?.wholeMatch(of: messageID) else {
                previousSender = nil
                continue
            }
            let bodies = item.all(Locators.messageBody)
            guard bodies.count == 1, let body = bodies.first else {
                skippedItems += 1
                previousSender = nil
                continue
            }

            let nodes = body.descendants()
            let senderButtons = nodes.filter(Locators.senderButton.matches)
            let title = senderButtons.count == 1 ? senderButtons.first?.string(.title) : nil
            let sender = senderButtons.isEmpty ? previousSender : title.flatMap { $0.isEmpty ? nil : $0 }
            let sections = nodes.filter(Locators.richTextSection.matches).map { section in
                section.descendants().compactMap { node in
                    node.role == "AXStaticText" ? node.string(.value) : nil
                }.joined()
            }
            let hasAttachments = nodes.contains { node in
                node.domClasses.contains { $0.hasPrefix(Locators.attachmentPrefix) }
            }
            let reactions = nodes.filter(Locators.reaction.matches).map { node in
                let title = node.string(.title) ?? ""
                let label = title.isEmpty ? node.string(.description) ?? "" : title
                return Reaction(label: label, reacted: node.domClasses.contains(Locators.reactionReacted))
            }

            messages.append(Message(ts: String(match.1), sender: sender,
                                    senderInherited: senderButtons.isEmpty && sender != nil,
                                    text: sections.joined(separator: "\n"), hasAttachments: hasAttachments,
                                    reactions: reactions))
            previousSender = sender
        }

        if let limit, limit < messages.count {
            messages = Array(messages.suffix(max(0, limit)))
        }
        return (messages, skippedItems)
    }
}
