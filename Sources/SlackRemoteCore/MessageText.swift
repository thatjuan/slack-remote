import Foundation

/// Validates and normalizes message text before sending it to Slack.
public enum MessageText {
    public static func isEmojiName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[a-z0-9_+'-]+/#) != nil
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
        let broadcasts = ["@channel", "@here", "@everyone", "<!channel>", "<!here>", "<!everyone>"]
        if !allowBroadcast, broadcasts.contains(where: {
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
}
