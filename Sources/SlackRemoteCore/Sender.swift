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
            previous = try newestTimestamp()
            button = try sendControl(broadcast: alsoSendToChannel, deadline: deadline) { controls in
                guard try controls.state() == expected, controls.pendingFiles.isEmpty else {
                    throw RemoteError.writeUnverified(draftLeft: true)
                }
            }
        } catch {
            throw composer.observedFailure(error)
        }

        let expectedMessage = MessageText.collapse(text)
        do {
            let ts = try pressAndConfirm(button, after: previous, deadline: deadline,
                                         unconfirmed: .sendUnconfirmed) { message, _ in
                !message.emojiOmitted && MessageText.collapse(message.text) == expectedMessage
            }
            return Receipt(method: method, ts: ts)
        } catch {
            throw composer.observedFailure(RemoteError.sendUnconfirmed)
        }
    }

    func newestTimestamp() throws -> String? {
        let before = try composer.freshView()
        let list = try composer.scope.list(in: before)
        let newest = list.children.compactMap(composer.scope.timestamp).max()
        try Composer.requireLiveDestination(before)
        return newest
    }

    /// The AX result alone cannot establish whether Slack sent the message.
    func pressAndConfirm(_ button: any UINode, after previous: String?, deadline: Date,
                         unconfirmed: RemoteError, matches: (Message, any UINode) -> Bool) throws -> String {
        try? button.perform(.press)
        do {
            if let ts = try Poll.until(deadline, {
                let view = try composer.freshView()
                let state = try composer.controls(in: view).state()
                try Composer.requireLiveDestination(view)
                guard state == .empty else { return nil as String? }
                let list = try composer.scope.list(in: view)
                let rows = MessageReader.readList(list, scope: composer.scope).rows
                let match = rows.first { row in
                    (previous.map { row.item.ts > $0 } ?? true) && matches(row.item, row.node)
                }
                try Composer.requireLiveDestination(view)
                return match?.item.ts
            }) { return ts }
        } catch {
            throw unconfirmed
        }
        throw unconfirmed
    }

    func sendControl(broadcast: Bool, deadline: Date,
                     verify: (Composer.Controls) throws -> Void) throws -> any UINode {
        func verifiedControls(in view: VerifiedView) throws -> Composer.Controls {
            let controls = try composer.controls(in: view)
            try verify(controls)
            guard controls.enabled == true else { throw RemoteError.writeUnverified(draftLeft: true) }
            return controls
        }

        var final = try composer.freshView()
        if case .thread(let thread) = composer.scope {
            let checkbox = try broadcastCheckbox(for: thread, in: final)
            if checkbox.bool(.value) != broadcast {
                _ = try verifiedControls(in: final)
                try composer.requireMutation(final, deadline: deadline)
                try? checkbox.perform(.press)
                final = try composer.freshView()
            }
            guard try broadcastCheckbox(for: thread, in: final).bool(.value) == broadcast else {
                throw RemoteError.writeUnverified(draftLeft: true)
            }
        }
        let controls = try verifiedControls(in: final)
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

}
