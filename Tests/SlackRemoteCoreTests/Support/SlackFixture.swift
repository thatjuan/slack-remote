import SlackRemoteCore

enum SlackFixture {
    static func window(team: String = "T0AAAAAAA", conversation: String = "C0BBBBBBB",
                       sidebar: [String] = ["C0BBBBBBB", "D0CCCCCCC"], isMain: Bool = true) -> FakeNode {
        let rows = sidebar.map { id in
            let classes = Locators.sidebarRow.classes + (id == conversation ? [Locators.sidebarRowSelected] : [])
            let control = FakeNode(role: "AXGroup", subrole: "AXApplicationGroup",
                                   domClasses: ["p-channel_sidebar__channel"])
            return FakeNode(role: "AXRow", subrole: "AXOutlineRow", domClasses: classes, domID: id, children: [control])
        }
        let outline = FakeNode(role: "AXOutline", domClasses: ["c-virtual_list__scroll_container"], children: rows)
        let list = FakeNode(role: "AXList", subrole: "AXContentList")
        let pane = FakeNode(role: "AXGroup", domClasses: ["p-message_pane"], children: [list])
        let editor = FakeNode(role: "AXTextArea", domClasses: ["ql-editor", Locators.composerBlank],
                              attributes: [.value: .string("")])
        let send = FakeNode(role: "AXButton", domClasses: Locators.sendButton.classes + [Locators.buttonDisabled],
                            attributes: [.enabled: .bool(false)])
        let composer = FakeNode(role: "AXGroup", domClasses: ["p-message_input_unstyled"], children: [editor, send])
        let primary = FakeNode(role: "AXGroup", domClasses: ["p-view_contents", "p-view_contents--primary"],
                               children: [pane, composer])
        let web = FakeNode(role: "AXWebArea", children: [outline, primary],
                           attributes: [.url: .string("https://app.slack.com/client/\(team)/\(conversation)")])
        return FakeNode(role: "AXWindow", children: [FakeNode(role: "AXGroup", children: [web])],
                        attributes: [.main: .bool(isMain), .minimized: .bool(false)])
    }
}
