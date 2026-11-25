public struct Message: Encodable, Equatable {
    public let ts: String
    public let sender: String?
    public let senderInherited: Bool
    public let text: String
    public let hasAttachments: Bool
    public let reactions: [Reaction]
    public let emojiOmitted: Bool

    private enum CodingKeys: String, CodingKey {
        case ts, sender, senderInherited, text, hasAttachments, reactions, emojiOmitted
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ts, forKey: .ts)
        try container.encode(sender, forKey: .sender)
        try container.encode(senderInherited, forKey: .senderInherited)
        try container.encode(text, forKey: .text)
        try container.encode(hasAttachments, forKey: .hasAttachments)
        try container.encode(reactions, forKey: .reactions)
        if emojiOmitted { try container.encode(true, forKey: .emojiOmitted) }
    }
}

public struct Reaction: Encodable, Equatable {
    public let label: String
    public let reacted: Bool
}

public enum MessageReader {
    private static let timestamp = #/[0-9]{10}\.[0-9]{6}/#

    public static func isTimestamp(_ value: String) -> Bool {
        value.wholeMatch(of: timestamp) != nil
    }

    public static func read(_ view: VerifiedView, scope: MessageScope = .primary, limit: Int?) throws
        -> (messages: [Message], skippedItems: Int) {
        let list = try scope.list(in: view)
        let rendered = readList(list, scope: scope)
        let rows = limit.map { Array(rendered.rows.suffix(max(0, $0))) } ?? rendered.rows
        return (rows.map(\.item), rendered.skipped.count)
    }

    static func readList(_ list: any UINode, scope: MessageScope = .primary)
        -> (rows: [(key: String, node: any UINode, item: Message)], skipped: [String]) {
        var rows: [(key: String, node: any UINode, item: Message)] = []
        var skipped: [String] = []
        var previousSender: String?

        for item in list.children {
            // A gap in the rendered message sequence ends sender inheritance.
            guard let ts = scope.timestamp(of: item) else {
                previousSender = nil
                continue
            }
            let bodies = item.all(Locators.messageBody)
            guard bodies.count == 1, let body = bodies.first else {
                skipped.append(ts)
                previousSender = nil
                continue
            }

            let nodes = body.descendants()
            let senderButtons = nodes.filter(Locators.senderButton.matches)
            let title = senderButtons.count == 1 ? senderButtons.first?.string(.title) : nil
            let sender = senderButtons.isEmpty ? previousSender : title.flatMap { $0.isEmpty ? nil : $0 }
            var emojiOmitted = false
            let sections = nodes.filter(Locators.richTextSection.matches).map { section in
                section.descendants().compactMap { node in
                    if node.role == "AXStaticText" { return node.string(.value) }
                    if Locators.emojiImage.matches(node) {
                        if let name = MessageText.emojiName(from: node.string(.title)) { return ":\(name):" }
                        emojiOmitted = true
                    }
                    return nil
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

            let message = Message(ts: ts, sender: sender,
                                  senderInherited: senderButtons.isEmpty && sender != nil,
                                  text: sections.joined(separator: "\n"), hasAttachments: hasAttachments,
                                  reactions: reactions, emojiOmitted: emojiOmitted)
            rows.append((key: message.ts, node: item, item: message))
            previousSender = sender
        }

        return (rows, skipped)
    }
}
