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

    /// Closes a modal owned by the caller and waits for the primary view to return.
    public static func closeModal(in tree: SlackTree, deadline: Date) throws {
        do {
            try tree.refresh()
            let window = try SlackWindow.currentWindow(in: tree).window
            let overlays = open(in: tree)
            if overlays == [.modal], blockingNodes(in: window).contains(where: { $0.kind == .modal }) {
                let backdrop = try window.one(Locators.modalOverlay)
                // AX can report an error for a press that Slack already handled.
                try? backdrop.perform(.press)
            } else if !overlays.isEmpty {
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
        try tree.refresh()
        try requireUnblocked(in: tree)
        var observedModal = false
        let result = Result {
            try opening()
            let modal: (any UINode)? = try Poll.until(deadline) {
                try tree.refresh()
                let window = try SlackWindow.currentWindow(in: tree).window
                let modals = blockingNodes(in: window).filter { $0.kind == .modal }
                return open(in: tree) == [.modal] ? modals.first?.node : nil
            }
            guard let modal else { throw RemoteError.timeout }
            observedModal = true
            return try body(modal)
        }

        do {
            try tree.refresh()
        } catch {
            throw RemoteError.overlayLeftOpen
        }
        if observedModal || !open(in: tree).isEmpty {
            try closeModal(in: tree, deadline: deadline)
        }
        return try result.get()
    }

    static func kind(_ node: any UINode) -> OverlayKind? {
        if node.role == "AXSheet" { return .sheet }
        if node.domClasses.contains(Locators.modalContent) { return .modal }
        return nil
    }

    private static func blockingNodes(in window: any UINode) -> [(kind: OverlayKind, node: any UINode)] {
        let nodes = window.descendants()
        let hasPrimaryView = nodes.filter(Locators.primaryView.matches).count == 1
        return nodes.compactMap { node in
            guard let kind = kind(node) else { return nil }
            // Slack uses ReactModal for informational tooltips while the conversation stays usable.
            if kind == .modal, hasPrimaryView, Locators.informationalTooltip.matches(node) { return nil }
            return (kind, node)
        }
    }
}
