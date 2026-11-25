@testable import SlackRemoteCore
import Testing

final class SelfPreviewFixture {
    let destination = Destination(team: TeamID("T0AAAAAAA")!, conversation: ConversationID("D0CCCCCCC")!)
    let window = SlackFixture.window(conversation: "D0CCCCCCC")
    let tree: SlackTree
    let web: FakeNode
    let row: FakeNode
    let editor: FakeNode
    let send: FakeNode
    let portal: FakeNode
    let backdrop: FakeNode
    let popup: FakeNode
    var config = Config()

    init() throws {
        let window = self.window
        tree = SlackTree(refresh: { [window] })
        window.subrole = "AXStandardWindow"
        web = try #require(try window.one(Locators.webArea) as? FakeNode)
        let selfID = destination.conversation.rawValue
        row = try #require(window.all(Locators.sidebarRow).first { $0.domID == selfID } as? FakeNode)
        row.domClasses.append(Locators.selfDM)
        let target = try #require(try row.one(Locators.sidebarRowTarget) as? FakeNode)
        target.attributes[.enabled] = .bool(true)
        target.actionNames = [UIAction.press.rawValue]
        editor = try #require(try window.one(Locators.composerEditor) as? FakeNode)
        editor.attributes[.enabled] = .bool(true)
        editor.attributes[.focused] = .bool(true)
        editor.settableAttributes = [.value, .focused]
        send = try #require(try window.one(Locators.sendButton) as? FakeNode)
        send.actionNames = [UIAction.press.rawValue]
        let link = FakeNode(role: "AXLink", domClasses: Locators.attachmentPopoverLink.classes,
                            children: [FakeNode(role: "AXStaticText")])
        popup = FakeNode(role: "AXGroup", domClasses: Locators.attachmentPopover.classes,
                         children: [link, FakeNode(role: "AXStaticText"), FakeNode(role: "AXStaticText")],
                         attributes: [.focused: .bool(false)])
        backdrop = FakeNode(role: "AXGroup", domClasses: Locators.attachmentPopoverBackdrop.classes, children: [popup],
                            attributes: [.focused: .bool(false)])
        portal = FakeNode(role: "AXGroup", domClasses: Locators.modalPortal.classes, children: [backdrop])
        web.children.append(portal)
        config.saveAccount(Account(team: destination.team, user: UserID("U0DDDDDDD")!, selfDM: destination.conversation))
        config.destinations["self"] = destination
        config.restrictWritesToDestinations = true
    }

    func setDraft(_ text: String) {
        let empty = text.isEmpty
        editor.attributes[.value] = .string(text)
        editor.domClasses = Locators.composerEditor.classes + (empty ? [Locators.composerBlank] : [])
        send.domClasses = Locators.sendButton.classes + (empty ? [Locators.buttonDisabled] : [])
        send.attributes[.enabled] = .bool(!empty)
    }
}
