import Foundation
@testable import SlackRemoteCore
import Testing

final class ThreadFixture {
    static let root = "1700000000.000100"
    static let reply = "1700000001.000100"
    static let otherRoot = "1700000010.000100"

    let primary: ComposerFixture
    let threadComposer: ComposerFixture
    let pane: FakeNode
    let list: FakeNode
    let broadcast: FakeNode
    let close: FakeNode

    init(root: String = ThreadFixture.root) throws {
        primary = try ComposerFixture()
        threadComposer = try ComposerFixture()
        let destination = primary.view.destination
        let prefix = VerifiedThread.itemPrefix(destination, rootTs: root)
        let item = MessageFixtures.message(0, sections: [[MessageFixtures.text("synthetic root")]])
        item.domID = prefix + root
        let input = MessageFixtures.item(id: prefix + "input", children: [threadComposer.editor, threadComposer.send])
        list = FakeNode(role: "AXList", subrole: "AXContentList", domClasses: ["sr-only"], children: [item, input])
        broadcast = FakeNode(role: "AXCheckBox", domClasses: Locators.threadBroadcast.classes,
                             domID: "p-thread_footer__broadcast_checkbox--\(destination.conversation.rawValue)-\(root)--Thread",
                             attributes: [.value: .bool(false)])
        close = FakeNode(role: "AXButton", domClasses: Locators.closeThread.classes)
        let menu = FakeNode(role: "AXPopUpButton", domClasses: Locators.closeThread.classes)
        let header = FakeNode(role: "AXToolbar", domClasses: Locators.threadHeader.classes, children: [menu, close])
        pane = FakeNode(role: "AXGroup", subrole: "AXApplicationDialog",
                        domClasses: ["p-view_contents"] + Locators.secondaryView.classes,
                        children: [header, list, broadcast])
        primary.webArea.children.append(pane)
        close.onPerform = { [weak self] _ in
            guard let self else { return }
            primary.webArea.children.removeAll { ($0 as? FakeNode) === self.pane }
        }
    }

    func verify(root: String = ThreadFixture.root) throws -> VerifiedThread {
        try ThreadView.verifyThread(primary.view.destination, rootTs: root, in: primary.tree)
    }

    func appendReply(_ text: String) {
        let item = MessageFixtures.message(1, sections: [[MessageFixtures.text(text)]])
        let prefix = VerifiedThread.itemPrefix(primary.view.destination, rootTs: Self.root)
        item.domID = prefix + Self.reply
        list.children.insert(item, at: list.children.count - 1)
    }

    func sender(beforeFinalGate: @escaping () -> Void = {}) throws -> Sender {
        let thread = try verify()
        let window = primary.window
        let editor = threadComposer.editor
        var refreshesAfterWrite = 0
        let tree = SlackTree(refresh: {
            if editor.setCalls.contains(where: { $0.attribute == .selectedText }) {
                refreshesAfterWrite += 1
                if refreshesAfterWrite == 3 { beforeFinalGate() }
            }
            return [window]
        })
        threadComposer.scriptWrite(accepting: .selectedText)
        return Sender(composer: Composer(view: primary.view, scope: .thread(thread), in: tree,
            methods: .init(selectedText: true, value: false, clear: .value)))
    }

    func scriptSend(_ text: String) {
        threadComposer.send.onPerform = { [weak self] _ in
            self?.threadComposer.show(.empty)
            self?.appendReply(text)
        }
    }
}

final class MessagePopupFixture {
    let webArea: FakeNode
    let modal: FakeNode
    let backdrop = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
    let menu = FakeNode(role: "AXMenu", domClasses: Locators.messageMenu.classes)
    let item: FakeNode

    init(webArea: FakeNode, item: FakeNode, mark: FakeNode? = nil) {
        self.webArea = webArea
        self.item = mark ?? item
        modal = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent], children: [menu])
        item.onPerform = { [weak self] action in
            if action == .showMenu { self?.open() }
        }
        backdrop.onPerform = { [weak self] _ in self?.dismiss() }
    }

    func open() {
        item.domClasses.append(Locators.contextMenuVisible)
        webArea.children.append(contentsOf: [backdrop, modal])
    }

    func replaceMenu(with picker: FakeNode) {
        item.domClasses.removeAll { $0 == Locators.contextMenuVisible }
        modal.children = [picker]
    }

    func dismiss() {
        webArea.children.removeAll { node in
            guard let fake = node as? FakeNode else { return false }
            return fake === backdrop || fake === modal
        }
        item.domClasses.removeAll { $0 == Locators.contextMenuVisible }
    }
}
