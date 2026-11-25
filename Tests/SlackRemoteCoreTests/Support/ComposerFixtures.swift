import Foundation
@testable import SlackRemoteCore
import Testing

final class ComposerFixture {
    let window = SlackFixture.window()
    let tree: SlackTree
    let view: VerifiedView
    let editor: FakeNode
    let send: FakeNode
    let list: FakeNode
    let webArea: FakeNode

    init() throws {
        let window = self.window
        tree = SlackTree(refresh: { [window] })
        let team = try #require(TeamID("T0AAAAAAA"))
        let conversation = try #require(ConversationID("C0BBBBBBB"))
        view = try SlackWindow.verify(Destination(team: team, conversation: conversation), in: tree)
        editor = try #require(try window.one(Locators.composerEditor) as? FakeNode)
        send = try #require(try window.one(Locators.sendButton) as? FakeNode)
        list = try #require(try window.one(Locators.messageList) as? FakeNode)
        webArea = try #require(try window.one(Locators.webArea) as? FakeNode)
    }

    func composer(selectedText: Bool = true, value: Bool = true) -> Composer {
        Composer(view: view, in: tree, methods: .init(selectedText: selectedText, value: value, clear: .value))
    }

    func sender(beforeFinalGate: @escaping () -> Void = {}) -> Sender {
        var refreshesAfterWrite = 0
        let tree = SlackTree(refresh: { [window, editor] in
            if editor.setCalls.contains(where: { $0.attribute == .selectedText }) {
                refreshesAfterWrite += 1
                // The first two snapshots observe the write and the message baseline.
                if refreshesAfterWrite == 3 { beforeFinalGate() }
            }
            return [window]
        })
        return Sender(composer: Composer(view: view, in: tree,
                                         methods: .init(selectedText: true, value: true, clear: .value)))
    }

    func show(_ state: ComposerState) {
        switch state {
        case .empty: showText("", blank: true, enabled: false)
        case .pendingContent: showText("", blank: true, enabled: true)
        case .text(let text): showText(text, blank: false, enabled: true)
        }
    }

    func disableSend() {
        send.domClasses = Locators.sendButton.classes + [Locators.buttonDisabled]
        send.attributes[.enabled] = .bool(false)
    }

    func scriptWrite(accepting method: UIAttribute?, transform: @escaping (String) -> String = { $0 }) {
        editor.onSet = { [weak self] attribute, value in
            guard let self else { return }
            if attribute == .focused { editor.attributes[attribute] = value }
            if attribute == method, case .string(let text) = value {
                let value = transform(text)
                show(value.isEmpty ? .empty : .text(value))
            }
        }
    }

    func appendMessage(_ index: Int, text: String) {
        list.children.append(MessageFixtures.message(index, sections: [[MessageFixtures.text(text)]]))
    }

    func scriptPress(message: String?) {
        send.onPerform = { [weak self] _ in
            guard let self else { return }
            show(.empty)
            if let message { appendMessage(1, text: message) }
        }
    }

    private func showText(_ text: String, blank: Bool, enabled: Bool) {
        editor.domClasses = Locators.composerEditor.classes + (blank ? [Locators.composerBlank] : [])
        editor.attributes[.value] = .string(text)
        send.domClasses = Locators.sendButton.classes
        send.attributes[.enabled] = .bool(true)
        if !enabled { disableSend() }
    }
}
