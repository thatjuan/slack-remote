import Foundation

public struct Sender {
    public struct Receipt {
        public let method: WriteMethod
        public let ts: String
    }

    private let composer: Composer

    public init(view: VerifiedView, in tree: SlackTree, requireIdle: @escaping () throws -> Void) {
        self.init(composer: Composer(view: view, in: tree, requireIdle: requireIdle))
    }

    init(composer: Composer) {
        self.composer = composer
    }

    public func send(_ text: String, deadline: Date) throws -> Receipt {
        let method = try composer.write(text, deadline: deadline)
        let expected = ComposerState.text(MessageText.normalize(text))

        let button: any UINode
        let previous: String?
        do {
            let before = try composer.freshView()
            previous = try MessageReader.read(before, limit: 1).messages.last?.ts
            try Composer.requireLiveDestination(before)

            let final = try composer.freshView()
            let controls = try composer.controls(in: final)
            guard try controls.state() == expected, controls.enabled == true else {
                throw RemoteError.writeUnverified(draftLeft: true)
            }
            try composer.requireMutation(final, deadline: deadline)
            button = controls.sendButton
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

                let messages = try MessageReader.read(view, limit: nil).messages
                let match = messages.first { message in
                    Self.isNewer(message.ts, than: previous) && MessageText.collapse(message.text) == expectedMessage
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

    private static func isNewer(_ ts: String, than previous: String?) -> Bool {
        guard let previous else { return true }
        func components(_ ts: String) -> (Int, Int)? {
            let parts = ts.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, let seconds = Int(parts[0]), let fraction = Int(parts[1]) else { return nil }
            return (seconds, fraction)
        }
        guard let current = components(ts), let baseline = components(previous) else { return false }
        return current > baseline
    }
}
