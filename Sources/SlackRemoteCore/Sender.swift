import Foundation

public struct Sender {
    public struct Receipt {
        public let method: WriteMethod
        public let ts: String
    }

    private let composer: Composer

    public init(view: VerifiedView, scope: MessageScope = .primary, in tree: SlackTree,
                requireIdle: @escaping () throws -> Void) {
        self.init(composer: Composer(view: view, scope: scope, in: tree, requireIdle: requireIdle))
    }

    init(composer: Composer) {
        self.composer = composer
    }

    public func send(_ text: String, alsoSendToChannel: Bool = false, deadline: Date) throws -> Receipt {
        if alsoSendToChannel, case .primary = composer.scope {
            throw RemoteError.unsafeText(reason: "broadcast_requires_thread")
        }
        let method = try composer.write(text, deadline: deadline)
        let expected = ComposerState.text(MessageText.normalize(text))

        let button: any UINode
        let previous: String?
        do {
            let before = try composer.freshView()
            let list = try composer.scope.list(in: before)
            previous = list.children.compactMap(composer.scope.timestamp).max()
            try Composer.requireLiveDestination(before)

            button = try sendControl(expecting: expected, broadcast: alsoSendToChannel, deadline: deadline)
        } catch {
            throw composer.observedFailure(error)
        }

        // The AX result alone cannot establish whether Slack sent the message.
        try? button.perform(.press)
        let expectedMessage = MessageText.collapse(text)
        do {
            let ts = try Poll.until(deadline) {
                let view = try composer.freshView()
                let state = try composer.controls(in: view).state()
                try Composer.requireLiveDestination(view)
                guard state == .empty else { return nil as String? }

                let messages = try MessageReader.read(view, scope: composer.scope, limit: nil).messages
                let match = messages.first { message in
                    (previous.map { message.ts > $0 } ?? true)
                        && !message.emojiOmitted && MessageText.collapse(message.text) == expectedMessage
                }
                try Composer.requireLiveDestination(view)
                return match?.ts
            }
            if let ts { return Receipt(method: method, ts: ts) }
        } catch {
            throw composer.observedFailure(RemoteError.sendUnconfirmed)
        }

        throw composer.observedFailure(RemoteError.sendUnconfirmed)
    }

    private func sendControl(expecting expected: ComposerState, broadcast: Bool, deadline: Date) throws -> any UINode {
        var final = try composer.freshView()
        if case .thread(let thread) = composer.scope {
            let checkbox = try broadcastCheckbox(for: thread, in: final)
            if checkbox.bool(.value) != broadcast {
                try requireDraft(expecting: expected, in: final)
                try composer.requireMutation(final, deadline: deadline)
                try? checkbox.perform(.press)
                final = try composer.freshView()
                let refreshed = try broadcastCheckbox(for: thread, in: final)
                guard refreshed.bool(.value) == broadcast else {
                    throw RemoteError.writeUnverified(draftLeft: true)
                }
            }
        }
        let controls = try requireDraft(expecting: expected, in: final)
        try composer.requireMutation(final, deadline: deadline)
        return controls.sendButton
    }

    private func broadcastCheckbox(for thread: VerifiedThread, in view: VerifiedView) throws -> any UINode {
        let pane = try composer.scope.node(in: view)
        let box = try pane.one(Locators.threadBroadcast)
        let id = "p-thread_footer__broadcast_checkbox--\(thread.destination.conversation.rawValue)-\(thread.rootTs)--Thread"
        guard box.domID == id, box.bool(.value) != nil else {
            throw RemoteError.uiDrift(locator: Locators.threadBroadcast.name, found: 0)
        }
        return box
    }

    @discardableResult
    private func requireDraft(expecting expected: ComposerState, in view: VerifiedView) throws -> Composer.Controls {
        let controls = try composer.controls(in: view)
        guard try controls.state() == expected, controls.enabled == true else {
            throw RemoteError.writeUnverified(draftLeft: true)
        }
        return controls
    }
}
