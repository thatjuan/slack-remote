import Foundation
@testable import SlackRemoteCore

enum DirectoryFixtures {
    static let destination = Destination(team: TeamID("T0AAAAAAA")!, conversation: ConversationID("C0BBBBBBB")!)

    static func sidebarRow(_ id: String?, name: String = "Project", classes: [String] = [],
                           selected: Bool = false) -> FakeNode {
        let text = FakeNode(role: "AXStaticText", attributes: [.value: .string(name)])
        let channel = FakeNode(role: "AXGroup", domClasses: Locators.sidebarRowTarget.classes + classes, children: [text])
        return FakeNode(role: "AXRow", subrole: "AXOutlineRow",
                        domClasses: Locators.sidebarRow.classes + (selected ? [Locators.sidebarRowSelected] : []),
                        domID: id, children: [channel])
    }

    static func memberRow(_ id: String, label: String = "Ada Lovelace") -> FakeNode {
        let button = FakeNode(role: "AXButton", attributes: [.title: .string(label)])
        return FakeNode(role: "AXGroup", domClasses: Locators.memberRow.classes, domID: id, children: [button])
    }

    static func bounds(items: Int = 500, pages: Int = 100) -> PageBounds {
        return PageBounds(maxItems: items, maxPages: pages, deadline: Date().addingTimeInterval(2))
    }
}

final class MemberModalFixture {
    let window = SlackFixture.window()
    let opener = FakeNode(role: "AXButton", domClasses: Locators.memberDetails.classes)
    let close = FakeNode(role: "AXButton", domClasses: Locators.aboutClose.classes)
    let tab = FakeNode(role: "AXRadioButton", domID: "members")
    private(set) var isOpen = false

    var tree: SlackTree { SlackTree(refresh: { [self.window] }) }

    init(rows: [FakeNode], tabTitle: String?) throws {
        tab.attributes = [.value: .bool(true)]
        if let tabTitle { tab.attributes[.title] = .string(tabTitle) }
        let toolbar = FakeNode(role: "AXToolbar", domClasses: Locators.conversationHeader.classes, children: [opener])
        let primary = try window.one(Locators.primaryView) as! FakeNode
        let web = try window.one(Locators.webArea) as! FakeNode
        primary.children.append(toolbar)
        let modal = FakeNode(role: "AXGroup", domClasses: Locators.aboutModal.classes, children: [tab, close] + rows)
        let backdrop = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes, children: [modal])
        let closedChildren = web.children
        opener.onPerform = { [weak self] _ in
            web.children = [backdrop]
            self?.isOpen = true
        }
        close.onPerform = { [weak self] _ in
            web.children = closedChildren
            self?.isOpen = false
        }
    }
}
