import Foundation
@testable import SlackRemoteCore
import Testing

final class SearchModalFixture {
    let destination = Destination(team: TeamID("T0AAAAAAA")!, conversation: ConversationID("C0BBBBBBB")!)
    let search = FakeNode(role: "AXButton", domClasses: ["p-top_nav__search"])
    let field = FakeNode(role: "AXComboBox", domClasses: ["ql-editor"], attributes: [.value: .string("")])
    let backdrop = FakeNode(role: "AXGroup", domClasses: ["ReactModal__Overlay"])
    let submit = FakeNode(role: "AXGroup", domClasses: ["c-search_autocomplete__suggestion_item--query"])
    let clear = FakeNode(role: "AXButton", domClasses: ["c-search__input_box__clear"])
    let inFilter: FakeNode
    let unrelated = FakeNode(role: "AXCheckBox", domID: "quick-filter-in-G0FFFFFFF")
    let fromFilter = FakeNode(role: "AXCheckBox", domID: "quick-filter-from-U0EEEEEEE")
    let window: FakeNode
    let tree: SlackTree
    var didWriteQuery: (() -> Void)?
    private let web: FakeNode
    private let wrapper: FakeNode
    private let modal: FakeNode

    init(includeMatchingFilter: Bool = true, queryReadback: String? = nil) throws {
        inFilter = FakeNode(role: "AXCheckBox", domID: "quick-filter-in-C0BBBBBBB")
        window = SlackFixture.window()
        web = try #require(window.one(Locators.webArea) as? FakeNode)
        let conversation = web.children + [search]
        web.children = conversation
        modal = FakeNode(role: "AXGroup", domClasses: ["ReactModal__Content"], domID: "fixture-search-popup")
        wrapper = FakeNode(role: "AXGroup", domClasses: ["c-search_modal__wrapper"])
        modal.children = [field, submit, unrelated, fromFilter] + (includeMatchingFilter ? [inFilter] : [])
        backdrop.children = [modal]
        wrapper.children = [backdrop]
        tree = SlackTree(windows: [window])

        search.onPerform = { [wrapper, web] _ in web.children = [wrapper] }
        backdrop.onPerform = { [web] _ in web.children = conversation }
        submit.onPerform = { [web] _ in web.children = conversation }
        submit.actionNames = ["AXPress"]
        field.settableAttributes = [.value]
        clear.onPerform = { [weak self] _ in
            guard let self else { return }
            field.attributes[.value] = .string("")
            field.children = []
            modal.children.removeAll { $0.domClasses.contains("c-search__input_box__clear") }
        }
        field.onSet = { [weak self] attribute, value in
            guard let self else { return }
            guard attribute == .value, case .string(let text) = value else { return }
            field.attributes[.value] = .string(queryReadback ?? text)
            modal.children.append(clear)
            didWriteQuery?()
        }
        for filter in [inFilter, unrelated] {
            filter.actionNames = ["AXPress"]
            filter.onPerform = { [weak self, weak filter] _ in
                guard let self, let filter else { return }
                let selected = !filter.domClasses.contains("c-filter-pill--active")
                filter.domClasses = selected ? ["c-filter-pill--active"] : []
                let plain = field.string(.value) ?? ""
                if selected {
                    field.attributes[.value] = .string(plain.isEmpty ? "in:fixture " : plain + " in:fixture ")
                } else {
                    field.attributes[.value] = .string(plain.hasSuffix(" in:fixture ") ? String(plain.dropLast(12)) : "")
                }
                field.children = selected
                    ? [FakeNode(role: "AXGroup", domClasses: ["c-member_slug--search-filter"])] : []
            }
        }
    }

    func replaceSearchPopup() -> (clear: FakeNode, backdrop: FakeNode) {
        let clear = FakeNode(role: "AXButton", domClasses: ["c-search__input_box__clear"])
        let replacement = FakeNode(role: "AXGroup", domClasses: ["ReactModal__Content"],
                                   domID: modal.domID, children: [clear])
        let backdrop = FakeNode(role: "AXGroup", domClasses: ["ReactModal__Overlay"], children: [replacement])
        web.children = [backdrop]
        return (clear, backdrop)
    }

    func showPopup(backdropReady: Bool) {
        wrapper.children = [backdropReady ? backdrop : modal]
        web.children = [wrapper]
    }

    func run(query: String = "slack-remote test", filtered: Bool = true, in session: SlackTree? = nil,
             onOpen: () -> Void = {},
             read: () throws -> Void = {}) throws {
        try SearchModal.run(query: query,
                            filters: .init(conversation: filtered ? destination.conversation : nil,
                                           fromMe: false, hasLink: false, threadsOnly: false),
                            from: destination, account: nil, in: session ?? tree,
                            deadline: Date().addingTimeInterval(1), onOpen: onOpen, read: read)
    }
}

final class SearchResultsFixture {
    static let team = TeamID("T0AAAAAAA")!
    static let start = Destination(team: team, conversation: ConversationID("C0BBBBBBB")!)
    static let result = Destination(team: team, conversation: ConversationID("G0FFFFFFF")!)
    static let firstTimestamp = "1700000000.000100"
    static let secondTimestamp = "1700000000.000200"

    let list: FakeNode
    let messageTab: FakeNode
    let filesTab: FakeNode
    let tree: SlackTree
    let scopedClose: FakeNode?
    private let window: FakeNode
    private let web: FakeNode
    private let conversationNodes: [any UINode]
    private let root: FakeNode
    private(set) var links: [URL] = []

    init(rows: [FakeNode], atEnd: Bool = true) throws {
        window = SlackFixture.window()
        web = try #require(window.one(Locators.webArea) as? FakeNode)
        conversationNodes = web.children
        list = FakeNode(role: "AXList", subrole: "AXContentList",
                        domClasses: atEnd ? [] : ["c-virtual_list__scroll_container", "p-explorer_results__container--no-bottom-margin"],
                        children: rows)
        messageTab = FakeNode(role: "AXRadioButton", subrole: "AXTabButton",
                              domClasses: ["c-tabs__tab", "c-tabs__tab--active"], domID: "messages")
        filesTab = FakeNode(role: "AXRadioButton", subrole: "AXTabButton", domClasses: ["c-tabs__tab"], domID: "files")
        let sort = FakeNode(role: "AXPopUpButton", domID: "search-filter-sort-filter",
                            attributes: [.value: .string("most_relevant")])
        if atEnd {
            scopedClose = nil
            let results: any UINode = rows.isEmpty ? FakeNode(role: "AXGroup", domClasses: ["c-empty_state"]) : list
            root = FakeNode(role: "AXGroup", domClasses: ["p-view_contents--sidebar"],
                            children: [messageTab, filesTab, sort, results])
            web.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/search")
            web.children = [root]
        } else {
            for row in rows { row.domClasses = ["c-virtual_list__item"] }
            let close = FakeNode(role: "AXButton", domClasses: ["c-icon_button", "c-icon_button--size_medium", "c-icon_button--default"])
            close.actionNames = ["AXPress"]
            scopedClose = close
            let header = FakeNode(role: "AXGroup", domClasses: ["p-explorer_header", "p-explorer_header--search_in_channel"],
                                  children: [close])
            root = FakeNode(role: "AXGroup", domClasses: ["p-view_contents--secondary"], children: [header, list])
            web.children.append(root)
            close.onPerform = { [web, root] _ in
                web.children.removeAll { $0 as AnyObject === root }
            }
        }
        tree = SlackTree(windows: [window])

        filesTab.actionNames = ["AXPress"]
        filesTab.onPerform = { [weak self] _ in
            self?.messageTab.domClasses = ["c-tabs__tab"]
            self?.filesTab.domClasses = ["c-tabs__tab", "c-tabs__tab--active"]
            self?.list.children = [Self.row(id: "F0DDDDDDD", name: "fixture.txt")]
        }
    }

    static func message(_ ts: String, withID: Bool = true) -> FakeNode {
        let timestamp = withID ? ts.replacingOccurrences(of: ".", with: "") : ""
        let link = FakeNode(role: "AXLink", domClasses: ["c-timestamp", "c-timestamp--static"],
                            attributes: [.url: .string("https://fixture.slack.com/archives/G0FFFFFFF/p\(timestamp)")])
        link.actionNames = ["AXPress"]
        let result = row(id: "result-\(ts)", sender: "Ada", text: "fixture excerpt")
        result.children.append(link)
        return result
    }

    static func row(id: String?, name: String? = nil, sender: String? = nil, text: String? = nil,
                    conversation: String? = nil) -> FakeNode {
        var children: [FakeNode] = []
        if let name { children.append(FakeNode(role: "AXStaticText", attributes: [.value: .string(name)])) }
        if let sender {
            children.append(FakeNode(role: "AXButton", domClasses: ["c-message__sender_button"],
                                     attributes: [.title: .string(sender)]))
        }
        if let text {
            children.append(FakeNode(role: "AXGroup", domClasses: ["p-rich_text_section"], children: [
                FakeNode(role: "AXStaticText", attributes: [.value: .string(text)]),
            ]))
        }
        if let conversation {
            children.append(FakeNode(role: "AXLink", domID: conversation))
        }
        let node = FakeNode(role: "AXGroup", domClasses: ["listitem__iBnNh"], domID: id, children: children)
        node.actionNames = ["AXPress", "AXScrollToVisible"]
        return node
    }

    static func timestamp(in row: FakeNode) throws -> FakeNode {
        try #require(row.one(Locators.searchTimestamp) as? FakeNode)
    }

    func navigate(to destination: Destination, with message: String? = nil) throws {
        web.attributes[.url] = .string("https://app.slack.com/client/\(destination.team.rawValue)/\(destination.conversation.rawValue)")
        web.children = conversationNodes
        if let message {
            let primary = try #require(web.one(Locators.primaryView) as? FakeNode)
            primary.children.append(FakeNode(role: "AXGroup", domClasses: ["c-virtual_list__item"],
                                             domID: "message-list_\(message)"))
        }
    }

    func showScopedResults(in destination: Destination) {
        web.attributes[.url] = .string("https://app.slack.com/client/\(destination.team.rawValue)/\(destination.conversation.rawValue)")
    }

    func showConversationFilter() {
        root.children.append(FakeNode(role: "AXButton", domClasses: [Locators.searchFilterActive], domID: "filter-in"))
    }

    func navigator(restores: Bool = true) -> Navigator {
        Navigator(openLink: { [self] url in
            links.append(url)
            if restores { try navigate(to: Self.start) }
        }, frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
    }

    func read(type: String = "messages", maxItems: Int = 50, maxPages: Int = 20,
              timeout: TimeInterval = 1, allowPartial: Bool = false) throws -> SearchResults.Snapshot {
        try SearchResults.read(type: type, team: Self.team, in: tree,
                               bounds: .init(maxItems: maxItems, maxPages: maxPages,
                                             deadline: Date().addingTimeInterval(timeout)),
                               allowPartial: allowPartial)
    }
}
