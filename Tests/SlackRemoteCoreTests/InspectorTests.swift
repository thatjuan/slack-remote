import SlackRemoteCore
import Testing

@Test func revealsOnlyExactEmojiImageTitlesOnRequest() {
    let image = FakeNode(role: "AXImage", domClasses: ["c-emoji"], attributes: [.title: .string(":tada:")])
    let invalid = FakeNode(role: "AXImage", domClasses: ["c-emoji"], attributes: [.title: .string(":Private:")])
    let other = FakeNode(role: "AXImage", attributes: [.title: .string(":unrelated:")])
    let root = FakeNode(role: "AXWindow", children: [image, invalid, other])
    let standard = Inspector.describe(root, scope: .window, maxDepth: nil)
    let named = Inspector.describe(root, scope: .window, maxDepth: nil, emojiNames: true)
    #expect(!standard.contains("title="))
    #expect(named.contains("title=:tada:"))
    #expect(!named.contains("Private"))
    #expect(!named.contains("unrelated"))
}

struct InspectorTests {
    @Test func readsStructureOnlyMasksIDsAndSkipsEditableDescendants() {
        let child = FakeNode(role: "AXStaticText", domID: "must-not-visit")
        let editor = FakeNode(role: "AXTextArea", children: [child],
                              attributes: [.value: .string("private user text")])
        editor.actionNames = ["AXScrollToVisible"]
        editor.settableAttributes = [.value, .selectedText, .title]
        let root = FakeNode(role: "AXGroup", subrole: "AXApplicationGroup",
                            domClasses: ["room-C0BBBBBBB", "time_1700000000"], domID: "T0AAAAAAA-123456",
                            children: [editor], attributes: [.title: .string("private title"),
                                                              .description: .string("private description"),
                                                              .url: .string("https://example.invalid/private")])
        let text = Inspector.describe(root, scope: .window, maxDepth: nil)
        #expect(text == """
            AXGroup AXApplicationGroup classes=room-C§9 time_1§10 id=T§9-1§6
              AXTextArea actions=AXScrollToVisible settable=AXValue,AXSelectedText

            """)
        #expect(root.readCalls.isEmpty)
        #expect(editor.readCalls.isEmpty)
        #expect(child.readCalls.isEmpty)
    }
}
