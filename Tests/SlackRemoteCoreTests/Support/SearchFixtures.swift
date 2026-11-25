import Foundation
import SlackRemoteCore
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
    let tree: SlackTree
    private let wrapper: FakeNode
    private let modal: FakeNode

    init(includeMatchingFilter: Bool = true, queryReadback: String? = nil) throws {
        inFilter = FakeNode(role: "AXCheckBox", domID: "quick-filter-in-C0BBBBBBB")
        let window = SlackFixture.window()
        let web = try #require(window.one(Locators.webArea) as? FakeNode)
        let conversation = web.children + [search]
        web.children = conversation
        modal = FakeNode(role: "AXGroup", domClasses: ["ReactModal__Content"])
        wrapper = FakeNode(role: "AXGroup", domClasses: ["c-search_modal__wrapper"])
        modal.children = [field, submit, unrelated] + (includeMatchingFilter ? [inFilter] : [])
        backdrop.children = [modal]
        wrapper.children = [backdrop]
        tree = SlackTree(windows: [window])

        search.onPerform = { [wrapper] _ in web.children = [wrapper] }
        backdrop.onPerform = { _ in web.children = conversation }
        submit.onPerform = { _ in web.children = conversation }
        submit.actionNames = ["AXPress"]
        clear.onPerform = { [weak self] _ in
            guard let self else { return }
            field.attributes[.value] = .string("")
            field.children = []
            modal.children.removeAll { $0.domClasses.contains("c-search__input_box__clear") }
        }
        field.onSet = { [weak self] attribute, value in
            guard let self else { return }
            field.attributes[attribute] = value
            guard attribute == .selectedText, case .string(let text) = value else { return }
            field.attributes[.value] = .string((field.string(.value) ?? "") + (queryReadback ?? text))
            modal.children.append(clear)
        }
        for filter in [inFilter, unrelated] {
            filter.actionNames = ["AXPress"]
            filter.onPerform = { [weak self, weak filter] _ in
                guard let self, let filter else { return }
                let selected = filter.bool(.value) != true
                filter.attributes[.value] = .bool(selected)
                field.attributes[.value] = .string(selected ? "in:fixture " : "")
                field.children = selected
                    ? [FakeNode(role: "AXGroup", domClasses: ["c-member_slug--search-filter"])] : []
            }
        }
    }

    func run(query: String = "slack-remote test", filtered: Bool = true,
             read: () throws -> Void = {}) throws {
        try SearchModal.run(query: query,
                            filters: .init(conversation: filtered ? destination.conversation : nil,
                                           fromMe: false, hasLink: false, threadsOnly: false),
                            from: destination, account: nil, in: tree,
                            deadline: Date().addingTimeInterval(1), read: read)
    }
}
