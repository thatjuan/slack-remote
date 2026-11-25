import SlackRemoteCore
import Testing

enum MessageFixtures {
    static func window(with items: [FakeNode]) throws -> FakeNode {
        let window = SlackFixture.window()
        let list = try #require(try window.one(Locators.messageList) as? FakeNode)
        list.children.append(contentsOf: items)
        return window
    }

    static func message(_ index: Int, sender: String? = nil, sections: [[FakeNode]] = [],
                        extras: [FakeNode] = []) -> FakeNode {
        var children: [FakeNode] = []
        if let sender {
            children.append(FakeNode(role: "AXButton", domClasses: ["c-message__sender_button"],
                                     attributes: [.title: .string(sender)]))
        }
        children.append(contentsOf: sections.map {
            FakeNode(role: "AXGroup", domClasses: ["p-rich_text_section"], children: $0)
        })
        children.append(contentsOf: extras)
        let body = FakeNode(role: "AXGroup", subrole: "AXDocument",
                            domClasses: ["c-message_kit__hover"], children: children)
        return item(id: "message-list_\(1_700_000_000 + index).000100", children: [body])
    }

    static func item(id: String, children: [FakeNode] = []) -> FakeNode {
        FakeNode(role: "AXGroup", domClasses: ["c-virtual_list__item"], domID: id, children: children)
    }

    static func divider() -> FakeNode {
        item(id: "message-list_1700000000000-divider")
    }

    static func spacer() -> FakeNode {
        item(id: "message-list_bottomSpacer")
    }

    static func text(_ value: String) -> FakeNode {
        FakeNode(role: "AXStaticText", attributes: [.value: .string(value)])
    }

    static func attachment() -> FakeNode {
        FakeNode(role: "AXGroup", domClasses: ["c-message_attachment__media"])
    }

    static func reaction(title: String, description: String, reacted: Bool) -> FakeNode {
        let classes = reacted ? ["c-reaction", "c-reaction--reacted"] : ["c-reaction"]
        return FakeNode(role: "AXCheckBox", subrole: "AXToggleButton", domClasses: classes,
                        attributes: [.title: .string(title), .description: .string(description)])
    }
}
