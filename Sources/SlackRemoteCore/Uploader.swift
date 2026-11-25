import Foundation

public struct Uploader {
    public enum AttachMethod: String, Encodable {
        case filePanel = "file_panel"
        case filePaste = "file_paste"
    }

    public struct Receipt {
        public let ts: String
        public let attachMethod: AttachMethod
    }

    private let view: VerifiedView
    private let scope: MessageScope
    private let tree: SlackTree
    private let requireIdle: () throws -> Void
    private let requireAccount: (any UINode) throws -> Void
    private let composer: Composer

    public init(view: VerifiedView, scope: MessageScope = .primary, in tree: SlackTree,
                requireIdle: @escaping () throws -> Void, requireAccount: @escaping (any UINode) throws -> Void = { _ in }) {
        self.view = view
        self.scope = scope
        self.tree = tree
        self.requireIdle = requireIdle
        self.requireAccount = requireAccount
        composer = Composer(view: view, scope: scope, in: tree, requireIdle: requireIdle)
    }

    public func upload(_ file: FileStaging, text: String?, alsoSendToChannel: Bool, deadline: Date,
                       paste: @escaping () throws -> Void) throws -> Receipt {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw RemoteError.fileRejected(reason: "staging_failed")
        }
        let before = try composer.state()
        guard before == .empty else { throw Composer.conflict(before) }
        tree.unwindOnSignal = true
        return try file.withStagedFile(in: downloads) {
            try uploadStaged($0, text: text, alsoSendToChannel: alsoSendToChannel, deadline: deadline, paste: paste)
        }
    }

    func uploadStaged(_ staged: URL, text: String?, alsoSendToChannel: Bool, deadline: Date,
                      paste: (() throws -> Void)? = nil) throws -> Receipt {
        if alsoSendToChannel, case .primary = scope {
            throw RemoteError.unsafeText(reason: "broadcast_requires_thread")
        }
        let name = staged.lastPathComponent
        let panel = FilePanel(tree: tree, destination: view.destination, requireIdle: requireIdle,
                              requireAccount: requireAccount)
        let sender = Sender(composer: composer)
        var openAttempted = false
        var textAttempted = false
        var sendAttempted = false
        do {
            func pasteStagedFile() throws -> AttachMethod {
                guard let paste else { throw RemoteError.uiDrift(locator: "filePanelRowURL", found: 0) }
                try pasteFile(staged, deadline: deadline, paste: paste, attempted: { openAttempted = true })
                return .filePaste
            }
            let method: AttachMethod
            if view.passiveSelfPreview != nil {
                // Paste into the verified editor without opening a second popover.
                method = try pasteStagedFile()
            } else {
                do {
                    try panel.attach(staged, deadline: deadline, opening: {
                        let current = try composer.freshView()
                        _ = try requireEmpty(in: current)
                        let button = try scope.node(in: current).one(Locators.attachButton)
                        try composer.requireMutation(current, deadline: deadline)
                        try? button.perform(.press)
                    }, openingFile: { openAttempted = true })
                    method = .filePanel
                } catch is FilePanel.URLUnavailable {
                    method = try pasteStagedFile()
                }
            }
            try waitForPendingFile(name, deadline: deadline)
            if let text {
                let current = try composer.freshView()
                try requireAccount(current.window)
                textAttempted = true
                _ = try composer.write(text, withFile: name, deadline: deadline)
            }
            let previous = try sender.newestTimestamp()
            let expected = text.map(MessageText.normalize) ?? ""
            let button = try sender.sendControl(broadcast: alsoSendToChannel, deadline: deadline) { view, controls in
                try requireAccount(view.window)
                let pending = try PendingFile.require(name, in: controls.pendingFiles)
                let state = try controls.state()
                guard pending.removeControl() != nil,
                      text == nil ? state == .pendingContent : state == .text(expected) else {
                    throw RemoteError.writeUnverified(draftLeft: textAttempted)
                }
            }
            try tree.checkInterruption()
            sendAttempted = true
            let ts = try sender.pressAndConfirm(button, after: previous, deadline: deadline,
                                                unconfirmed: .uploadUnconfirmed) { message, row in
                guard message.hasAttachments else { return false }
                let files = row.all(Locators.sentFile)
                let names = files.flatMap { [$0.string(.title), $0.string(.description)].compactMap { $0 } }
                guard files.count <= 1, names.allSatisfy({ $0.utf8.elementsEqual(name.utf8) }) else {
                    return false
                }
                return text.map { !message.emojiOmitted && MessageText.collapse(message.text) == MessageText.collapse($0) }
                    ?? true
            }
            return Receipt(ts: ts, attachMethod: method)
        } catch {
            guard openAttempted else { throw error }
            let observed = tree.withCleanup {
                observeFailure(staged: staged, removingFile: !sendAttempted, textAttempted: textAttempted)
            }
            throw WriteFailure(error, draftLeft: observed.draftLeft, pendingFileLeft: observed.pendingFileLeft)
        }
    }

    private func requireEmpty(in current: VerifiedView) throws -> Composer.Controls {
        let controls = try composer.controls(in: current)
        let state = try controls.state()
        guard state == .empty else { throw Composer.conflict(state) }
        try requireAccount(current.window)
        return controls
    }

    private func pasteFile(_ staged: URL, deadline: Date, paste: () throws -> Void,
                           attempted: () -> Void) throws {
        let current = try composer.freshView()
        let controls = try requireEmpty(in: current)
        try composer.requireMutation(current, deadline: deadline)
        try controls.editor.set(.focused, to: .bool(true))
        try FilePaste.withURL(staged) { requireClipboard in
            let fresh = try composer.freshView()
            let focused = try requireEmpty(in: fresh)
            guard focused.editor.bool(.focused) == true else {
                throw RemoteError.writeUnverified(draftLeft: false)
            }
            try composer.requireMutation(fresh, deadline: deadline)
            try requireClipboard()
            attempted()
            // A native AX error can arrive after the action was accepted.
            try? paste()
            try waitForPendingFile(staged.lastPathComponent, deadline: deadline, requireReady: false)
        }
    }

    private func waitForPendingFile(_ name: String, deadline: Date, requireReady: Bool = true) throws {
        let found = try Poll.until(deadline) {
            let current = try composer.freshView()
            let controls = try composer.controls(in: current)
            try Composer.requireLiveDestination(current)
            guard !controls.pendingFiles.isEmpty else {
                if case .text = try controls.state() { throw RemoteError.writeUnverified(draftLeft: true) }
                return nil as Bool?
            }
            let pending = try PendingFile.require(name, in: controls.pendingFiles)
            return !requireReady || pending.removeControl() != nil ? true : nil
        }
        guard found == true else { throw RemoteError.writeUnverified(draftLeft: false) }
    }

    private func observeFailure(staged: URL, removingFile: Bool, textAttempted: Bool)
        -> (draftLeft: Bool?, pendingFileLeft: Bool) {
        var draftLeft: Bool? = textAttempted ? nil : false
        do {
            let current = try composer.freshView()
            let controls = try composer.controls(in: current)
            let state = try controls.state()
            let deadline = tree.cleanupDeadline(after: 3)
            if case .text(let text) = state {
                draftLeft = true
                if removingFile, !textAttempted, controls.pendingFiles.isEmpty, text == staged.absoluteString || text == staged.path {
                    try requireAccount(current.window)
                    if try composer.clear(expecting: text, deadline: deadline) { draftLeft = false }
                }
            } else {
                draftLeft = false
            }
            if controls.pendingFiles.isEmpty {
                return (draftLeft, state == .pendingContent)
            }
            guard removingFile, controls.pendingFiles.count == 1, let pending = controls.pendingFiles.first,
                  let control = pending.removeControl() else {
                return (draftLeft, true)
            }
            try requireAccount(current.window)
            try composer.requireMutation(current, deadline: deadline)
            try? control.perform(.press)
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
