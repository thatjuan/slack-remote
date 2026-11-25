import Foundation

public enum MessageText {
    public static func isEmojiName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[a-z0-9_+'-]+/#) != nil
    }

    static func emojiName(from label: String?) -> String? {
        guard let label, label.first == ":", label.last == ":", label.count > 2 else { return nil }
        let name = String(label.dropFirst().dropLast())
        return isEmojiName(name) ? name : nil
    }

    static func renderedEmojiName(_ node: any UINode) -> String? {
        if Locators.emojiImage.matches(node) { return emojiName(from: node.string(.title)) }
        guard Locators.emojiGroup.matches(node), node.children.count == 1,
              let image = node.children.first, image.role == "AXImage",
              let title = image.string(.title) else { return nil }
        if let name = emojiName(from: title) { return name }
        // Slack 4.53.292 exposes an image titled "<shortcode> emoji" inside the c-emoji group.
        return title.wholeMatch(of: #/([a-z0-9_+'-]+) emoji/#).map { String($0.1) }
    }

    public static func validate(_ text: String, allowBroadcast: Bool, checkEmojiNames: Bool = true) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RemoteError.unsafeText(reason: "blank_text") }
        guard text.count <= 4000 else { throw RemoteError.unsafeText(reason: "text_too_long") }
        guard !text.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t"
        }) else { throw RemoteError.unsafeText(reason: "control_character") }
        guard trimmed.first != "/" else { throw RemoteError.unsafeText(reason: "slash_command") }
        guard text.wholeMatch(of: #/\+:[^:\s]+:\s*/#) == nil else {
            throw RemoteError.unsafeText(reason: "reaction_shortcut")
        }
        if checkEmojiNames {
            let urls = text.ranges(of: #/[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^\s<>]+/#)
            for token in text.matches(of: #/:([^:\s]+):/#) {
                if !urls.contains(where: { $0.contains(token.range.lowerBound) }),
                   !isEmojiName(String(token.1)) {
                    throw RemoteError.unsafeText(reason: "invalid_emoji_name")
                }
            }
        }
        if !allowBroadcast, ["@channel", "@here", "@everyone"].contains(where: {
            text.range(of: $0, options: .caseInsensitive) != nil
        }) {
            throw RemoteError.unsafeText(reason: "broadcast_mention")
        }
    }

    public static func normalize(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n").precomposedStringWithCanonicalMapping
        if normalized.last == "\n" { normalized.removeLast() }
        return normalized
    }

    public static func collapse(_ text: String) -> String {
        normalize(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
