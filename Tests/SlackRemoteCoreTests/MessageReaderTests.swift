import Foundation
import SlackRemoteCore
import Testing

struct MessageReaderTests {
    private let target = Destination(team: TeamID("T0AAAAAAA")!, conversation: ConversationID("C0BBBBBBB")!)

    private func view(of window: FakeNode) throws -> VerifiedView {
        try SlackWindow.verify(target, in: SlackTree(windows: [window]))
    }

    private func read(_ items: [FakeNode], limit: Int? = nil) throws -> (messages: [Message], skippedItems: Int) {
        try MessageReader.read(view(of: MessageFixtures.window(with: items)), limit: limit)
    }

    @Test func joinsRichTextSections() throws {
        let message = MessageFixtures.message(0, sender: "Ada", sections: [
            [MessageFixtures.text("Deploy is done.")],
            [MessageFixtures.text("Logs look clean.")],
        ])
        let result = try read([message])
        let first = try #require(result.messages.first)
        #expect(result.messages.count == 1)
        #expect(first.ts == "1700000000.000100")
        #expect(first.sender == "Ada")
        #expect(!first.senderInherited)
        #expect(first.text == "Deploy is done.\nLogs look clean.")
    }

    @Test func includesLinkTextInOrder() throws {
        let link = FakeNode(role: "AXLink", children: [MessageFixtures.text("the report")])
        let message = MessageFixtures.message(0, sections: [
            [MessageFixtures.text("Read "), link, MessageFixtures.text(" today.")],
        ])
        let result = try read([message])
        #expect(result.messages.map(\.text) == ["Read the report today."])
    }

    @Test func emitsNamedEmojiInPlaceAndMarksAnOmittedEmoji() throws {
        let named = FakeNode(role: "AXImage", domClasses: ["c-emoji"], attributes: [.title: .string(":tada:")])
        let unnamed = FakeNode(role: "AXImage", domClasses: ["c-emoji"], attributes: [.title: .string("Emoji")])
        let result = try read([
            MessageFixtures.message(0, sections: [[MessageFixtures.text("Before "), named, MessageFixtures.text(" after")]]),
            MessageFixtures.message(1, sections: [[MessageFixtures.text("Unnamed"), unnamed]]),
        ])
        #expect(result.messages.map(\.text) == ["Before :tada: after", "Unnamed"])
        #expect(result.messages.map(\.emojiOmitted) == [false, true])
        let data = try JSONEncoder().encode(result.messages)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(json[0]["emojiOmitted"] == nil)
        #expect(json[1]["emojiOmitted"] as? Bool == true)
    }

    @Test func inheritsOnlyAnAvailableSender() throws {
        let result = try read([
            MessageFixtures.message(0),
            MessageFixtures.message(1, sender: "Ada"),
            MessageFixtures.message(2),
        ])
        #expect(result.messages.map(\.sender) == [nil, "Ada", "Ada"])
        #expect(result.messages.map(\.senderInherited) == [false, false, true])

        let first = try #require(result.messages.first)
        let data = try JSONEncoder().encode(first)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["sender"] is NSNull)
    }

    @Test func ignoresDividersAndSpacers() throws {
        let spacer = MessageFixtures.spacer()
        let divider = MessageFixtures.divider()
        let result = try read([
            MessageFixtures.message(0, sender: "Ada"),
            divider,
            MessageFixtures.message(1),
            spacer,
        ])
        #expect(result.messages.map(\.ts) == ["1700000000.000100", "1700000001.000100"])
        #expect(result.messages.map(\.sender) == ["Ada", nil])
        #expect(result.skippedItems == 0)

        let empty = try read([divider, spacer])
        #expect(empty.messages.isEmpty)
        #expect(empty.skippedItems == 0)
    }

    @Test func skipsMatchingItemWithoutBody() throws {
        let result = try read([
            MessageFixtures.message(0, sender: "Ada"),
            MessageFixtures.item(id: "message-list_1700000001.000100"),
            MessageFixtures.message(2),
        ])
        #expect(result.skippedItems == 1)
        #expect(result.messages.map(\.ts) == ["1700000000.000100", "1700000002.000100"])
        #expect(result.messages.map(\.sender) == ["Ada", nil])
        #expect(result.messages.map(\.senderInherited) == [false, false])
    }

    @Test func readsReactionLabelsAndState() throws {
        let message = MessageFixtures.message(0, extras: [
            MessageFixtures.reaction(title: "2 check marks", description: "Check mark", reacted: true),
            MessageFixtures.reaction(title: "", description: "1 wave", reacted: false),
        ])
        let result = try read([message])
        let first = try #require(result.messages.first)
        #expect(first.reactions.map(\.label) == ["2 check marks", "1 wave"])
        #expect(first.reactions.map(\.reacted) == [true, false])
    }

    @Test func detectsAttachment() throws {
        let result = try read([
            MessageFixtures.message(0),
            MessageFixtures.message(1, extras: [MessageFixtures.attachment()]),
        ])
        #expect(result.messages.map(\.hasAttachments) == [false, true])
        #expect(result.messages.map(\.text) == ["", ""])
    }

    @Test func keepsNewestMessagesInTreeOrder() throws {
        let items = [
            MessageFixtures.message(0, sender: "Ada"),
            MessageFixtures.message(1),
            MessageFixtures.message(2, sender: "Grace"),
        ]
        let result = try read(items, limit: 2)
        #expect(result.messages.map(\.ts) == ["1700000001.000100", "1700000002.000100"])
        #expect(result.messages.map(\.sender) == ["Ada", "Grace"])
        #expect(result.messages.map(\.senderInherited) == [true, false])
        #expect(try read(items, limit: 0).messages.isEmpty)
    }

    @Test func rejectsMultipleMessageLists() throws {
        let window = SlackFixture.window()
        let primary = try #require(try window.one(Locators.primaryView) as? FakeNode)
        primary.children.append(FakeNode(role: "AXList", subrole: "AXContentList", domClasses: ["sr-only"],
                                         children: [MessageFixtures.spacer()]))
        let view = try view(of: window)
        let error = #expect(throws: RemoteError.self) { try MessageReader.read(view, limit: nil) }
        #expect(error?.code == "ui_drift")
        guard case .uiDrift(let locator, let found)? = error else { return }
        #expect(locator == "messageList")
        #expect(found == 2)
    }

    @Test func readsConversationWithNestedContentList() throws {
        let bullet = FakeNode(role: "AXListItem", children: [MessageFixtures.text("A nested bullet")])
        let nested = FakeNode(role: "AXList", subrole: "AXContentList", domClasses: ["sr-only"], children: [bullet])
        let message = MessageFixtures.message(0, sender: "Ada", sections: [[MessageFixtures.text("A message")]],
                                              extras: [nested])

        let result = try read([message])
        #expect(result.messages.map(\.text) == ["A message"])
    }
}
