import Foundation

public struct Uploader {
    public enum AttachMethod: String, Encodable {
        case filePanel = "file_panel"
    }

    public struct Receipt {
        public let ts: String
        public let attachMethod: AttachMethod
    }

    private let view: VerifiedView
    private let scope: MessageScope
    private let tree: SlackTree
    private let requireIdle: () throws -> Void
    private let composer: Composer

    public init(view: VerifiedView, scope: MessageScope = .primary, in tree: SlackTree,
                requireIdle: @escaping () throws -> Void) {
        self.view = view
        self.scope = scope
        self.tree = tree
        self.requireIdle = requireIdle
        composer = Composer(view: view, scope: scope, in: tree, requireIdle: requireIdle)
    }

    public func upload(_ file: FileStaging, text: String?, alsoSendToChannel: Bool, deadline: Date) throws -> Receipt {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw RemoteError.fileRejected(reason: "staging_failed")
        }
        let before = try composer.state()
        guard before == .empty else { throw Composer.conflict(before) }
        tree.unwindOnSignal = true
        return try file.withStagedFile(in: downloads) {
            try uploadStaged($0, text: text, alsoSendToChannel: alsoSendToChannel, deadline: deadline)
        }
    }

    func uploadStaged(_ staged: URL, text: String?, alsoSendToChannel: Bool, deadline: Date) throws -> Receipt {
        if alsoSendToChannel, case .primary = scope {
            throw RemoteError.unsafeText(reason: "broadcast_requires_thread")
        }
        let name = staged.lastPathComponent
        let panel = FilePanel(tree: tree, destination: view.destination, requireIdle: requireIdle)
        let sender = Sender(composer: composer)
        var openAttempted = false
        var textAttempted = false
        var sendAttempted = false
        do {
            try panel.attach(staged, deadline: deadline, opening: {
                let current = try composer.freshView()
                let controls = try composer.controls(in: current)
                let state = try controls.state()
                guard state == .empty else { throw Composer.conflict(state) }
                let button = try scope.node(in: current).one(Locators.attachButton)
                try composer.requireMutation(current, deadline: deadline)
                try? button.perform(.press)
            }, openingFile: { openAttempted = true })

            try waitForPendingFile(name, deadline: deadline)
            if let text {
                textAttempted = true
                _ = try composer.write(text, withFile: name, deadline: deadline)
            }
            let previous = try sender.newestTimestamp()
            let expected = text.map(MessageText.normalize) ?? ""
            let button = try sender.sendControl(broadcast: alsoSendToChannel, deadline: deadline) { controls in
                try PendingFile.require(name, in: controls.pendingFiles)
                let state = try controls.state()
                guard text == nil ? state == .pendingContent : state == .text(expected) else {
                    throw RemoteError.writeUnverified(draftLeft: textAttempted)
                }
            }
            try tree.checkInterruption()
            sendAttempted = true
            let ts = try sender.pressAndConfirm(button, after: previous, deadline: deadline,
                                                unconfirmed: .uploadUnconfirmed) { message, row in
                guard message.hasAttachments else { return false }
                let names = row.all(Locators.sentFileName).compactMap { $0.string(.value) }
                guard names.isEmpty || names.contains(where: { $0.utf8.elementsEqual(name.utf8) }) else {
                    return false
                }
                return text.map { !message.emojiOmitted && MessageText.collapse(message.text) == MessageText.collapse($0) }
                    ?? true
            }
            return Receipt(ts: ts, attachMethod: .filePanel)
        } catch {
            guard openAttempted else { throw error }
            let observed = tree.withCleanup {
                observeFailure(removingFile: !sendAttempted, textAttempted: textAttempted)
            }
            throw WriteFailure(error, draftLeft: observed.draftLeft, pendingFileLeft: observed.pendingFileLeft)
        }
    }

    private func waitForPendingFile(_ name: String, deadline: Date) throws {
        let found = try Poll.until(deadline) {
            let current = try composer.freshView()
            let controls = try composer.controls(in: current)
            try Composer.requireLiveDestination(current)
            guard !controls.pendingFiles.isEmpty else { return nil as Bool? }
            try PendingFile.require(name, in: controls.pendingFiles)
            return true
        }
        guard found == true else { throw RemoteError.writeUnverified(draftLeft: false) }
    }

    private func observeFailure(removingFile: Bool, textAttempted: Bool)
        -> (draftLeft: Bool?, pendingFileLeft: Bool) {
        var draftLeft: Bool? = textAttempted ? nil : false
        do {
            let current = try composer.freshView()
            let controls = try composer.controls(in: current)
            if textAttempted {
                draftLeft = try !controls.editorText().isEmpty
            }
            if controls.pendingFiles.isEmpty {
                return (draftLeft, try controls.state() == .pendingContent)
            }
            let deadline = tree.cleanupDeadline(after: 3)
            guard removingFile, controls.pendingFiles.count == 1, let pending = controls.pendingFiles.first else {
                return (draftLeft, true)
            }
            try composer.requireMutation(current, deadline: deadline)
            try? pending.remove()
            let removed = try Poll.until(deadline) {
                let fresh = try composer.freshView()
                let current = try composer.controls(in: fresh)
                try Composer.requireLiveDestination(fresh)
                let state = try current.state()
                return current.pendingFiles.isEmpty && state != .pendingContent ? true : nil
            }
            return (draftLeft, removed != true)
        } catch {
            return (draftLeft, true)
        }
    }
}
