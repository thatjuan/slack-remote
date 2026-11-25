import Foundation

public enum ComposerState: Equatable {
    case empty
    case text(String)
    case pendingContent
}

public enum WriteMethod: String, Encodable {
    case selectedText = "selected_text"
    case value
    case existing
}

/// A post-mutation failure. Nil draftLeft means the destination could not be re-observed.
public struct WriteFailure: Error {
    public let error: RemoteError
    public let draftLeft: Bool?
    public let pendingFileLeft: Bool?

    init(_ error: any Error, draftLeft: Bool?, pendingFileLeft: Bool? = nil) {
        self.error = (error as? WriteFailure)?.error ?? error as? RemoteError
            ?? .internalError(operation: "mutate_composer")
        self.draftLeft = draftLeft
        self.pendingFileLeft = pendingFileLeft
    }

    public var details: [String: RemoteError.Detail]? {
        var details = error.details ?? [:]
        details["draftLeft"] = draftLeft.map(RemoteError.Detail.boolean)
        details["pendingFileLeft"] = pendingFileLeft.map(RemoteError.Detail.boolean)
        return details.isEmpty ? nil : details
    }
}

public struct Composer {
    enum ClearMethod { case selectedText, value }

    struct Methods {
        let selectedText: Bool
        let value: Bool
        let clear: ClearMethod?

        // Slack acknowledges AXSelectedText but leaves the editor unchanged. AXValue updates Quill.
        static let live = Methods(selectedText: false, value: true, clear: .value)
    }

    private let view: VerifiedView
    let scope: MessageScope
    private let tree: SlackTree?
    private let methods: Methods
    private let requireIdle: () throws -> Void

    public init(view: VerifiedView) {
        self.init(view: view, in: nil, methods: .live)
    }

    public init(view: VerifiedView, scope: MessageScope = .primary, in tree: SlackTree,
                requireIdle: @escaping () throws -> Void) {
        self.init(view: view, scope: scope, in: tree, methods: .live, requireIdle: requireIdle)
    }

    init(view: VerifiedView, scope: MessageScope = .primary, in tree: SlackTree?, methods: Methods,
         requireIdle: @escaping () throws -> Void = {}) {
        self.view = view
        self.scope = scope
        self.tree = tree
        self.methods = methods
        self.requireIdle = requireIdle
    }

    struct Controls {
        let editor: any UINode
        let sendButton: any UINode
        let pendingFiles: [PendingFile]

        var enabled: Bool? {
            if sendButton.domClasses.contains(Locators.buttonDisabled) { return false }
            return sendButton.bool(.enabled)
        }

        func state() throws -> ComposerState {
            if editor.domClasses.contains(Locators.composerBlank) {
                if !pendingFiles.isEmpty { return .pendingContent }
                guard let enabled else { throw RemoteError.uiDrift(locator: "sendButton.enabled", found: 0) }
                return enabled ? .pendingContent : .empty
            }
            return .text(try editorText())
        }

        func editorText() throws -> String {
            guard let value = editor.string(.value) else {
                throw RemoteError.uiDrift(locator: "composerEditor.value", found: 0)
            }
            return MessageText.normalize(value)
        }
    }

    func controls(in view: VerifiedView) throws -> Controls {
        let node = try scope.node(in: view)
        return try Controls(editor: node.one(Locators.composerEditor),
                            sendButton: node.one(Locators.sendButton), pendingFiles: PendingFile.all(in: node))
    }

    public func state() throws -> ComposerState {
        let current = try freshView()
        let state = try controls(in: current).state()
        try Self.requireLiveDestination(current)
        return state
    }

    public func write(_ text: String, deadline: Date) throws -> WriteMethod {
        try write(text, withFile: nil, deadline: deadline)
    }

    func write(_ text: String, withFile file: String?, deadline: Date) throws -> WriteMethod {
        let expected = MessageText.normalize(text)
        let startingState: ComposerState = file == nil ? .empty : .pendingContent
        let initial = try freshView()
        let controls = try controls(in: initial)
        let current = try controls.state()
        try Self.requireLiveDestination(initial)
        if let file { try PendingFile.require(file, in: controls.pendingFiles) }
        if file == nil, controls.pendingFiles.isEmpty, current == .text(expected) { return .existing }
        guard current == startingState, file != nil || controls.pendingFiles.isEmpty else {
            throw Self.conflict(current)
        }
        guard tree != nil else { throw RemoteError.writeFailed(draftLeft: false) }

        var attempted = false
        do {
            if methods.selectedText {
                let focused = try editableControls(expecting: startingState, file: file, deadline: deadline)
                if (try? focused.editor.set(.focused, to: .bool(true))) != nil {
                    let focusedAgain = try editableControls(expecting: startingState, file: file, deadline: deadline)
                    if focusedAgain.editor.bool(.focused) == true {
                        attempted = true
                        // Classify the result by read-back even if AX reports an error.
                        try? focusedAgain.editor.set(.selectedText, to: .string(text))
                        if try verifyWrite(expected, startingState: startingState, file: file, deadline: deadline) {
                            return .selectedText
                        }
                    }
                }
            }
            if methods.value {
                let controls = try editableControls(expecting: startingState, file: file, deadline: deadline)
                attempted = true
                try? controls.editor.set(.value, to: .string(text))
                if try verifyWrite(expected, startingState: startingState, file: file, deadline: deadline) {
                    return .value
                }
            }
            throw RemoteError.writeFailed(draftLeft: false)
        } catch let failure as WriteFailure {
            throw failure
        } catch {
            if attempted { throw observedFailure(error) }
            throw error
        }
    }

    /// Returns whether there was a draft to clear.
    @discardableResult
    public func clear(expecting text: String, deadline: Date) throws -> Bool {
        let expected = ComposerState.text(MessageText.normalize(text))
        let initial = try freshView()
        let current = try controls(in: initial).state()
        try Self.requireLiveDestination(initial)
        if current == .empty { return false }
        guard current == expected else { throw Self.conflict(current) }
        guard tree != nil, let method = methods.clear else {
            throw WriteFailure(RemoteError.writeFailed(draftLeft: true), draftLeft: try? state() != .empty)
        }

        let (view, controls) = try matchingControls(expecting: expected, file: nil)
        let rawValue = controls.editor.string(.value)
        guard let rawValue, .text(MessageText.normalize(rawValue)) == expected else {
            throw Self.conflict(try state())
        }
        try requireMutation(view, deadline: deadline)
        var attempted = false
        do {
            switch method {
            case .selectedText:
                try controls.editor.set(.selectedTextRange, to: .range(location: 0, length: rawValue.utf16.count))
                let (view, selected) = try matchingControls(expecting: expected, file: nil)
                guard selected.editor.string(.value)?.utf16.elementsEqual(rawValue.utf16) == true,
                      selected.editor.string(.selectedText)?.utf16.elementsEqual(rawValue.utf16) == true else {
                    throw observedFailure(RemoteError.writeUnverified(draftLeft: true))
                }
                try requireMutation(view, deadline: deadline)
                attempted = true
                try? selected.editor.set(.selectedText, to: .string(""))
            case .value:
                attempted = true
                try? controls.editor.set(.value, to: .string(""))
            }
            func isCleared() throws -> Bool {
                let current = try state()
                if current == .empty { return true }
                guard current == expected else {
                    throw WriteFailure(RemoteError.writeUnverified(draftLeft: true), draftLeft: true)
                }
                return false
            }
            if try Poll.until(methodDeadline(deadline), { try isCleared() ? true : nil }) == true { return true }
            if try isCleared() { return true }
            throw RemoteError.writeUnverified(draftLeft: true)
        } catch {
            if let failure = error as? WriteFailure { throw failure }
            if attempted { throw observedFailure(error) }
            throw error
        }
    }

    func freshView() throws -> VerifiedView {
        guard let tree else {
            try Overlays.requireUnblocked(in: SlackTree(windows: [view.window]))
            return view
        }
        try tree.refresh()
        return try SlackWindow.verify(view.destination, in: tree)
    }

    static func requireLiveDestination(_ view: VerifiedView) throws {
        let webArea = try view.window.one(Locators.webArea)
        let location = webArea.string(.url).map(ClientLocation.parse) ?? .notClient
        guard location.destination == view.destination else {
            throw RemoteError.destinationMismatch(expected: view.destination, actual: location)
        }
    }

    func requireMutation(_ view: VerifiedView, deadline: Date) throws {
        try requireIdle()
        try Self.requireLiveDestination(view)
        guard Date() < deadline else { throw RemoteError.timeout }
    }

    func observedFailure(_ error: any Error) -> WriteFailure {
        WriteFailure(error, draftLeft: try? state() != .empty)
    }

    private func editableControls(expecting expected: ComposerState, file: String?, deadline: Date) throws -> Controls {
        let (fresh, controls) = try matchingControls(expecting: expected, file: file)
        try requireMutation(fresh, deadline: deadline)
        return controls
    }

    private func matchingControls(expecting expected: ComposerState, file: String?) throws -> (VerifiedView, Controls) {
        let fresh = try freshView()
        let controls = try controls(in: fresh)
        let current = try controls.state()
        guard current == expected else { throw Self.conflict(current) }
        if let file { try PendingFile.require(file, in: controls.pendingFiles) }
        else if !controls.pendingFiles.isEmpty { throw Self.conflict(current) }
        return (fresh, controls)
    }

    private func verifyWrite(_ expected: String, startingState: ComposerState, file: String?, deadline: Date)
        throws -> Bool {
        func matches() throws -> Bool {
            let fresh = try freshView()
            let controls = try controls(in: fresh)
            let state = try controls.state()
            if let file { try PendingFile.require(file, in: controls.pendingFiles) }
            try Self.requireLiveDestination(fresh)
            if state == startingState { return false }
            if state == .text(expected) { return true }
            throw WriteFailure(RemoteError.writeUnverified(draftLeft: true), draftLeft: true)
        }
        if try Poll.until(methodDeadline(deadline), { try matches() ? true : nil }) == true { return true }
        return try matches()
    }

    private func methodDeadline(_ deadline: Date) -> Date {
        min(deadline, Date().addingTimeInterval(2))
    }

    static func conflict(_ state: ComposerState) -> RemoteError {
        if case .text(let text) = state { return .draftConflict(existingLength: text.count) }
        return .draftConflict(existingLength: 0)
    }
}
