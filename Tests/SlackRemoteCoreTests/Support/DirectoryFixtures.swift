import Foundation
@testable import SlackRemoteCore
import XCTest

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

final class ChannelBrowserFixture {
    let browse = FakeNode(role: "AXMenuItem", domClasses: Locators.addChannelsMenuItem.classes,
                          domID: "menu-8-1", attributes: [.title: .string("Browse channels")])
    let backdrop = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
    let replacement = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes, children: [
        FakeNode(role: "AXGroup", subrole: "AXApplicationDialog", domClasses: [Locators.modalContent]),
    ])
    let tree: SlackTree
    private let web: FakeNode
    private let startingChildren: [any UINode]
    private let directory: FakeNode
    private(set) var links: [URL] = []

    init() throws {
        let window = SlackFixture.window()
        web = try XCTUnwrap(window.one(Locators.webArea) as? FakeNode)
        startingChildren = web.children
        tree = SlackTree(windows: [window])
        let tab = FakeNode(role: "AXRadioButton", subrole: "AXTabButton",
                           domClasses: Locators.directoryTab.classes + [Locators.activeTabClass], domID: "channels")
        let list = FakeNode(role: "AXList", domClasses: Locators.directoryChannels.classes, children: [
            Self.channel("C0AAAAAAA", name: "General"),
            Self.channel("C0BBBBBBB", name: "Notes"),
        ])
        directory = FakeNode(role: "AXGroup", subrole: "AXTabPanel", domClasses: Locators.directoryTabPanel.classes,
                             children: [tab, list])
        let opener = FakeNode(role: "AXPopUpButton")
        let row = DirectoryFixtures.sidebarRow(Locators.sidebarEndID)
        row.children = [opener]
        let sidebar = try XCTUnwrap(window.one(Locators.sidebarList) as? FakeNode)
        sidebar.children.append(row)
        let menu = FakeNode(role: "AXMenu", domClasses: ["c-menu__items"], children: [
            FakeNode(role: "AXMenuItem", domClasses: Locators.addChannelsMenuItem.classes,
                     domID: "menu-8-0", attributes: [.title: .string("Create a new channel")]),
            browse,
        ])
        backdrop.children = [FakeNode(role: "AXGroup", domClasses: [Locators.modalContent], children: [menu])]
        opener.onPerform = { [weak self] _ in
            guard let self else { return }
            web.children.append(backdrop)
        }
        backdrop.onPerform = { [weak self] _ in
            guard let self else { return }
            web.children = startingChildren
        }
        browse.onPerform = { [weak self] _ in self?.arriveInDirectory() }
    }

    func arriveInDirectory() {
        web.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA")
        web.children = [directory]
    }

    func replaceMenu() {
        arriveInDirectory()
        web.children.append(replacement)
    }

    func navigator() -> Navigator {
        Navigator(openLink: { [self] link in
            links.append(link)
            web.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/C0BBBBBBB")
            web.children = startingChildren
        }, frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
    }

    private static func channel(_ id: String, name: String) -> FakeNode {
        let label = FakeNode(role: "AXStaticText", attributes: [.value: .string(name)])
        let content = FakeNode(role: "AXGroup", domClasses: ["c-channel_search_result"], children: [label])
        return FakeNode(role: "AXGroup", domClasses: Locators.directoryChannelRow.classes,
                        domID: id, children: [content])
    }
}

final class MemberModalFixture {
    let window = SlackFixture.window()
    let opener = FakeNode(role: "AXButton", domClasses: Locators.memberDetails.classes)
    let close = FakeNode(role: "AXButton", domClasses: Locators.aboutClose.classes)
    let tab = FakeNode(role: "AXRadioButton", domClasses: [Locators.activeTabClass], domID: "members")
    private(set) var isOpen = false

    var tree: SlackTree { SlackTree(refresh: { [self.window] }) }

    init(rows: [FakeNode], tabTitle: String?, selected: Bool = true) throws {
        if !selected { tab.domClasses.removeAll() }
        if let tabTitle { tab.attributes[.title] = .string(tabTitle) }
        tab.onPerform = { [weak tab] _ in tab?.domClasses.append(Locators.activeTabClass) }
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
