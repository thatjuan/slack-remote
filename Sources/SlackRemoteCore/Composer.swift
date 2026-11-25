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

    init(_ error: any Error, draftLeft: Bool?) {
        self.error = error as? RemoteError ?? .internalError(operation: "mutate_composer")
        self.draftLeft = draftLeft
    }

    public var details: [String: RemoteError.Detail]? {
        var details = error.details ?? [:]
        details["draftLeft"] = draftLeft.map(RemoteError.Detail.boolean)
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
    private let tree: SlackTree?
    private let methods: Methods
    private let requireIdle: () throws -> Void

    public init(view: VerifiedView) {
        self.init(view: view, in: nil, methods: .live)
    }

    public init(view: VerifiedView, in tree: SlackTree, requireIdle: @escaping () throws -> Void) {
        self.init(view: view, in: tree, methods: .live, requireIdle: requireIdle)
    }

    init(view: VerifiedView, in tree: SlackTree?, methods: Methods, requireIdle: @escaping () throws -> Void = {}) {
        self.view = view
        self.tree = tree
        self.methods = methods
        self.requireIdle = requireIdle
    }

    struct Controls {
        let editor: any UINode
        let sendButton: any UINode

        var enabled: Bool? {
            if sendButton.domClasses.contains(Locators.buttonDisabled) { return false }
            return sendButton.bool(.enabled)
        }

        func state() throws -> ComposerState {
            if editor.domClasses.contains(Locators.composerBlank) {
                guard let enabled else { throw RemoteError.uiDrift(locator: "sendButton.enabled", found: 0) }
                return enabled ? .pendingContent : .empty
            }
            guard let value = editor.string(.value) else {
                throw RemoteError.uiDrift(locator: "composerEditor.value", found: 0)
            }
            return .text(MessageText.normalize(value))
        }
    }

    func controls(in view: VerifiedView) throws -> Controls {
        try Controls(editor: view.primaryView.one(Locators.composerEditor),
                     sendButton: view.primaryView.one(Locators.sendButton))
    }

    public func state() throws -> ComposerState {
        let current = try freshView()
        let state = try controls(in: current).state()
        try Self.requireLiveDestination(current)
        return state
    }

    public func write(_ text: String, deadline: Date) throws -> WriteMethod {
        let expected = MessageText.normalize(text)
        let initial = try freshView()
        let current = try controls(in: initial).state()
        try Self.requireLiveDestination(initial)
        if current == .text(expected) { return .existing }
        guard current == .empty else { throw Self.conflict(current) }
        guard tree != nil else { throw RemoteError.writeFailed(draftLeft: false) }

        var attempted = false
        do {
            if methods.selectedText {
                let focused = try editableControls(expecting: .empty, deadline: deadline)
                if (try? focused.editor.set(.focused, to: .bool(true))) != nil {
                    let focusedAgain = try editableControls(expecting: .empty, deadline: deadline)
                    if focusedAgain.editor.bool(.focused) == true {
                        attempted = true
                        // Classify the result by read-back even if AX reports an error.
                        try? focusedAgain.editor.set(.selectedText, to: .string(text))
                        if try verifyWrite(expected, deadline: deadline) { return .selectedText }
                    }
                }
            }
            if methods.value {
                let controls = try editableControls(expecting: .empty, deadline: deadline)
                attempted = true
                try? controls.editor.set(.value, to: .string(text))
                if try verifyWrite(expected, deadline: deadline) { return .value }
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

        let (view, controls) = try matchingControls(expecting: expected)
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
                let (view, selected) = try matchingControls(expecting: expected)
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

    private func editableControls(expecting expected: ComposerState, deadline: Date) throws -> Controls {
        let (fresh, controls) = try matchingControls(expecting: expected)
        try requireMutation(fresh, deadline: deadline)
        return controls
    }

    private func matchingControls(expecting expected: ComposerState) throws -> (VerifiedView, Controls) {
        let fresh = try freshView()
        let controls = try controls(in: fresh)
        let current = try controls.state()
        guard current == expected else { throw Self.conflict(current) }
        return (fresh, controls)
    }

    private func verifyWrite(_ expected: String, deadline: Date) throws -> Bool {
        func matches(_ state: ComposerState) throws -> Bool {
            if state == .empty { return false }
            if state == .text(expected) { return true }
            throw WriteFailure(RemoteError.writeUnverified(draftLeft: true), draftLeft: true)
        }
        if try Poll.until(methodDeadline(deadline), { try matches(state()) ? true : nil }) == true { return true }
        return try matches(state())
    }

    private func methodDeadline(_ deadline: Date) -> Date {
        min(deadline, Date().addingTimeInterval(2))
    }

    static func conflict(_ state: ComposerState) -> RemoteError {
        if case .text(let text) = state { return .draftConflict(existingLength: text.count) }
        return .draftConflict(existingLength: 0)
    }
}
