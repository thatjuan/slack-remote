import Foundation

public enum MessageText {
    public static func validate(_ text: String, allowBroadcast: Bool) throws {
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
