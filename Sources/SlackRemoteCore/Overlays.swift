import Foundation

public enum OverlayKind: Equatable { case modal, sheet }

public enum Overlays {
    /// Blocking overlays currently open in Slack's windows, in tree order.
    public static func open(in tree: SlackTree) -> [OverlayKind] {
        tree.windows.flatMap { blockingNodes(in: $0).map(\.kind) }
    }

    public static func requireUnblocked(in tree: SlackTree) throws {
        guard open(in: tree).isEmpty else { throw RemoteError.uiBlocked }
    }

    /// Returns the expected control inside the sole blocking modal in the current window.
    static func requireOnlyModal(containing locator: Locator, in tree: SlackTree) throws -> any UINode {
        let window = try SlackWindow.currentWindow(in: tree).window
        guard let modal = try selection(in: tree, window: window, within: nil)?.content else {
            throw RemoteError.uiDrift(locator: locator.name, found: 0)
        }
        return try modal.one(locator)
    }

    /// Closes a modal owned by the caller and waits for the primary view to return.
    public static func closeModal(in tree: SlackTree, deadline: Date) throws {
        try closeModal(in: tree, deadline: deadline, within: nil)
    }

    private static func closeModal(in tree: SlackTree, deadline: Date, within locator: Locator?) throws {
        do {
            try tree.refresh()
            let original = try SlackWindow.currentWindow(in: tree)
            func closeTarget(in window: any UINode) throws -> (scope: (any UINode)?, backdrop: (any UINode)?) {
                let scope: (any UINode)?
                if let locator {
                    scope = try container(in: window, matching: locator)
                } else {
                    scope = try selection(in: tree, window: window, within: nil)?.container
                }
                let target = scope.flatMap {
                    backdrop(in: window, scope: $0, within: locator, oneBlockingModal: open(in: tree) == [.modal])
                }
                return (scope, target)
            }
            var target = try closeTarget(in: original.window)
            // Search's filter can render before its backdrop. A fresh AX session exposes the owned backdrop.
            if locator != nil, target.scope != nil, target.backdrop == nil, !open(in: tree).contains(.sheet),
               let rebuild = tree.rebuildOwnedMode {
                try rebuild(deadline)
                let rebuilt = try SlackWindow.currentWindow(in: tree)
                guard rebuilt.location == original.location else { throw RemoteError.overlayLeftOpen }
                target = try closeTarget(in: rebuilt.window)
            }
            if let backdrop = target.backdrop {
                // AX can report an error for a press that Slack already handled.
                try? backdrop.perform(.press)
            } else if target.scope != nil {
                throw RemoteError.overlayLeftOpen
            }

            func primaryRestored() throws -> Bool {
                try tree.refresh()
                let current = try SlackWindow.currentWindow(in: tree)
                return open(in: tree).isEmpty && current.window.all(Locators.primaryView).count == 1
            }
            if try primaryRestored() { return }
            let closed: Bool? = try Poll.until(deadline) { try primaryRestored() ? true : nil }
            guard closed == true else { throw RemoteError.overlayLeftOpen }
        } catch {
            throw RemoteError.overlayLeftOpen
        }
    }

    /// Owns the one modal opened by opening and closes it even when body throws.
    public static func withModal<T>(in tree: SlackTree, deadline: Date,
                                    opening: () throws -> Void,
                                    _ body: (any UINode) throws -> T) throws -> T {
        try withModal(in: tree, deadline: deadline, within: nil, opening: opening, body)
    }

    /// Identify the caller's popup when Slack also displays an auxiliary dialog.
    static func withModal<T>(in tree: SlackTree, deadline: Date, within locator: Locator?,
                             replacedBySheet: Bool = false,
                             opening: () throws -> Void, _ body: (any UINode) throws -> T) throws -> T {
        try tree.refresh()
        try requireUnblocked(in: tree)
        var observedModal = false
        let result = Result {
            try opening()
            let modal: (any UINode)? = try Poll.until(deadline) {
                try tree.refresh()
                let window = try SlackWindow.currentWindow(in: tree).window
                guard !open(in: tree).contains(.sheet) else { throw RemoteError.uiBlocked }
                return try selection(in: tree, window: window, within: locator)?.content
            }
            guard let modal else { throw RemoteError.timeout }
            observedModal = true
            return try body(modal)
        }

        try tree.withCleanup {
            do {
                try tree.refresh()
            } catch {
                throw RemoteError.overlayLeftOpen
            }
            let overlays = open(in: tree)
            if replacedBySheet, observedModal, overlays == [.sheet] { return }
            if observedModal || !overlays.isEmpty {
                try closeModal(in: tree, deadline: max(deadline, tree.cleanupDeadline(after: 2)), within: locator)
            }
        }
        return try result.get()
    }

    static func onlySheet(in tree: SlackTree) throws -> (any UINode)? {
        let overlays = open(in: tree)
        if overlays.isEmpty { return nil }
        guard overlays == [.sheet] else { throw RemoteError.uiBlocked }
        return try SlackWindow.currentWindow(in: tree).window.one(Locators.fileSheet)
    }

    /// Cancels the owned native file sheet, including after an interruption.
    static func cancelSheet(in tree: SlackTree, deadline: Date) throws {
        try tree.withCleanup {
            do {
                try tree.refresh()
                guard let sheet = try onlySheet(in: tree) else { return }
                guard let cancel = sheet.node(.cancelButton), cancel.role == "AXButton" else {
                    throw RemoteError.overlayLeftOpen
                }
                try? cancel.perform(.press)
                let closed = try Poll.until(deadline) {
                    try tree.refresh()
                    return try onlySheet(in: tree) == nil ? true : nil
                }
                guard closed == true else { throw RemoteError.overlayLeftOpen }
            } catch {
                throw RemoteError.overlayLeftOpen
            }
        }
    }

    static func kind(_ node: any UINode) -> OverlayKind? {
        if node.role == "AXSheet" { return .sheet }
        if node.domClasses.contains(Locators.modalContent) { return .modal }
        return nil
    }

    private static func blockingNodes(in window: any UINode) -> [(kind: OverlayKind, node: any UINode)] {
        let nodes = window.descendants()
        let hasInformationalTooltip = nodes.filter(Locators.primaryView.matches).count == 1
            && nodes.filter { Locators.informationalTooltip.matches($0) && kind($0) == .modal }.count == 1
        return nodes.compactMap { node in
            guard let kind = kind(node) else { return nil }
            // Slack uses ReactModal for informational tooltips while the conversation stays usable.
            if kind == .modal, hasInformationalTooltip, Locators.informationalTooltip.matches(node) { return nil }
            return (kind, node)
        }
    }

    private static func selection(in tree: SlackTree, window: any UINode, within locator: Locator?)
        throws -> (content: any UINode, container: any UINode)? {
        if let locator {
            guard let container = try container(in: window, matching: locator) else { return nil }
            let modals = ([container] + container.descendants()).filter { kind($0) == .modal }
            guard modals.count <= 1 else {
                throw RemoteError.uiDrift(locator: Locators.modalContent, found: modals.count)
            }
            return modals.first.map { ($0, container) }
        }
        guard open(in: tree) == [.modal],
              let content = blockingNodes(in: window).first(where: { $0.kind == .modal })?.node,
              !Locators.informationalTooltip.matches(content) else { return nil }
        return (content, window)
    }

    private static func container(in window: any UINode, matching locator: Locator) throws -> (any UINode)? {
        let matches = window.all(locator)
        guard matches.count <= 1 else { throw RemoteError.uiDrift(locator: locator.name, found: matches.count) }
        return matches.first
    }

    private static func backdrop(in window: any UINode, scope: any UINode, within locator: Locator?,
                                 oneBlockingModal: Bool) -> (any UINode)? {
        if Locators.modalOverlay.matches(scope) { return scope }
        let all = window.all(Locators.modalOverlay).filter { $0.all(Locators.informationalTooltip).isEmpty }
        let scoped: [any UINode]
        if let locator {
            let associated = all.filter { $0.all(locator).count == 1 }
            scoped = associated.isEmpty && oneBlockingModal ? all : associated
        } else {
            scoped = all
        }
        return scoped.count == 1 ? scoped.first : nil
    }
}
