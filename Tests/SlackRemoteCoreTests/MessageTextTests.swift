import SlackRemoteCore
import Testing

struct MessageTextTests {
    @Test(arguments: [
        (" \n\t", "blank_text"),
        (String(repeating: "a", count: 4001), "text_too_long"),
        ("example\u{0007}", "control_character"),
        ("\t /status", "slash_command"),
        ("+:tada: \n", "reaction_shortcut"),
        ("example :Tada:", "invalid_emoji_name"),
        ("example :bad/name:", "invalid_emoji_name"),
        ("Good morning @ChAnNeL", "broadcast_mention"),
    ])
    func refusesUnsafeText(_ text: String, reason: String) {
        let error = #expect(throws: RemoteError.self) { try MessageText.validate(text, allowBroadcast: false) }
        guard case .unsafeText(let actual)? = error else {
            Issue.record("Expected unsafe_text")
            return
        }
        #expect(actual == reason)
    }

    @Test func allowBroadcastPermitsHere() throws {
        try MessageText.validate("Hello @here", allowBroadcast: true)
    }

    @Test func acceptsShortcodesUnicodeEmojiAndURLsWithPorts() throws {
        try MessageText.validate("Example :tada: 🎉 :+1: https://localhost:8080/path", allowBroadcast: false)
        #expect(MessageText.normalize("🎉") != MessageText.normalize(":tada:"))
    }

    @Test func normalizesLineEndingsTrailingNewlineAndUnicode() {
        let normalized = MessageText.normalize("e\u{0301}\r\nnext\r\n\r\n")
        #expect(Array(normalized.utf8) == Array("é\nnext\n".utf8))
    }

    @Test func collapseIgnoresOnlyWhitespaceLayout() {
        #expect(MessageText.collapse("hello\nthere\n") == MessageText.collapse("hello there"))
        #expect(MessageText.collapse("hello\nthere\n") != MessageText.collapse("hello again"))
    }
}
