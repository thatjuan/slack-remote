import Foundation

public struct MessageTarget {
    private let tree: SlackTree
    private let scope: MessageScope
    private let deadline: Date
    private let requireIdle: () throws -> Void

    public init(in tree: SlackTree, scope: MessageScope = .primary, deadline: Date,
                requireIdle: @escaping () throws -> Void) {
        self.tree = tree
        self.scope = scope
        self.deadline = deadline
        self.requireIdle = requireIdle
    }

    /// Pages toward the start only when the requested message is outside the rendered list.
    public func locate(ts: String, in view: VerifiedView, page: Bool) throws -> any UINode {
        if let item = try renderedItem(ts: ts, in: view) { return item }
        guard page else { throw RemoteError.messageNotRendered }
        try requireIdle()

        let paged = try VirtualListPager.collect(direction: .towardStart,
            bounds: PageBounds(maxItems: .max, maxPages: 20, deadline: deadline), rendered: {
                try tree.refresh()
                let fresh = try SlackWindow.verify(view.destination, in: tree)
                let rows = try scope.list(in: fresh).children.compactMap { node in
                    scope.timestamp(of: node).map { (key: $0, node: node, item: $0) }
                }
                guard Set(rows.map(\.key)).count == rows.count else {
                    throw RemoteError.uiDrift(locator: "messageItem", found: rows.count)
                }
                try Composer.requireLiveDestination(fresh)
                try requireIdle()
                return rows
            }, reachedBoundary: { $0 == ts }, atEnd: { false })
        guard paged.stopReason == .boundary else { throw RemoteError.messageNotRendered }

        try tree.refresh()
        let fresh = try SlackWindow.verify(view.destination, in: tree)
        guard let item = try renderedItem(ts: ts, in: fresh) else { throw RemoteError.messageNotRendered }
        return item
    }

    /// Opens the context menu and proves which item Slack marked as its owner.
    public func openMenu(ts: String, in view: VerifiedView) throws -> any UINode {
        _ = try locate(ts: ts, in: view, page: true)
        try tree.refresh()
        let fresh = try SlackWindow.verify(view.destination, in: tree)
        let target = try locate(ts: ts, in: fresh, page: false)
        try requireIdle()
        try Composer.requireLiveDestination(fresh)
        guard Date() < deadline else { throw RemoteError.timeout }

        do {
            try? target.perform(.showMenu)
            let menu = try Poll.until(deadline) {
                try tree.refresh()
                guard !Overlays.open(in: tree).isEmpty else { return nil as (any UINode)? }
                return try verifiedMenu(ts: ts, destination: view.destination)
            }
            guard let menu else { throw RemoteError.timeout }
            return menu
        } catch {
            try closeMenuIfOpen()
            throw error
        }
    }

    func verifiedMenu(ts: String, destination: Destination) throws -> any UINode {
        let popup = try Overlays.requireOnlyModal(containing: Locators.messageMenu, in: tree)
        let client = try SlackWindow.currentWindow(in: tree)
        guard client.location.destination == destination else {
            throw RemoteError.destinationMismatch(expected: destination, actual: client.location)
        }
        let marked = client.window.all(Locators.virtualItem).filter {
            $0.domClasses.contains(Locators.contextMenuVisible)
        }
        guard marked.count == 1, marked.first?.domID == scope.itemPrefix + ts else {
            throw RemoteError.uiDrift(locator: "contextMenuTarget", found: marked.count)
        }
        return popup
    }

    func closeMenuIfOpen() throws {
        do {
            try tree.refresh()
            if Overlays.open(in: tree).isEmpty { return }
            _ = try Overlays.requireOnlyModal(containing: Locators.messageMenu, in: tree)
            try Overlays.closeModal(in: tree, deadline: deadline)
        } catch {
            throw RemoteError.overlayLeftOpen
        }
    }

    private func renderedItem(ts: String, in view: VerifiedView) throws -> (any UINode)? {
        let items = try scope.list(in: view).children.filter { scope.timestamp(of: $0) == ts }
        guard items.count <= 1 else { throw RemoteError.uiDrift(locator: "messageItem", found: items.count) }
        return items.first
    }
}
