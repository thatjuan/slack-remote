import Foundation

public struct VerifiedThread {
    public let destination: Destination
    public let rootTs: String
    public let pane: any UINode

    var itemPrefix: String { Self.itemPrefix(destination, rootTs: rootTs) }

    static func itemPrefix(_ destination: Destination, rootTs: String) -> String {
        "\(destination.conversation.rawValue)-\(rootTs)\(Locators.threadItemMarker)"
    }
}

public enum ThreadView {
    public static func verifyThread(_ destination: Destination, rootTs: String, in tree: SlackTree) throws
        -> VerifiedThread {
        try verify(rootTs: rootTs, in: SlackWindow.verify(destination, in: tree))
    }

    static func verify(rootTs: String, in view: VerifiedView) throws -> VerifiedThread {
        let pane = try view.window.one(Locators.secondaryView)
        let thread = try identify(pane, destination: view.destination)
        guard thread.rootTs == rootTs else { throw RemoteError.uiDrift(locator: "threadIdentity", found: 0) }
        return thread
    }

    private static func identify(_ pane: any UINode, destination: Destination) throws -> VerifiedThread {
        let list = try pane.one(Locators.threadList)
        let rows = list.children.filter { Locators.virtualItem.matches($0) }
        let conversation = destination.conversation.rawValue + "-"
        guard let firstID = rows.first?.domID, firstID.hasPrefix(conversation),
              let split = firstID.range(of: Locators.threadItemMarker) else {
            throw RemoteError.uiDrift(locator: "threadIdentity", found: rows.count)
        }
        let rootTs = String(firstID[..<split.lowerBound].dropFirst(conversation.count))
        let prefix = VerifiedThread.itemPrefix(destination, rootTs: rootTs)
        guard MessageReader.isTimestamp(rootTs), rows.allSatisfy({ $0.domID?.hasPrefix(prefix) == true }),
              rows.contains(where: { $0.domID.map { MessageReader.isTimestamp(String($0.dropFirst(prefix.count))) } == true })
        else { throw RemoteError.uiDrift(locator: "threadIdentity", found: rows.count) }
        return VerifiedThread(destination: destination, rootTs: rootTs, pane: pane)
    }

    public static func open(_ destination: Destination, rootTs: String, in tree: SlackTree, deadline: Date,
                            requireIdle: @escaping () throws -> Void) throws -> VerifiedThread {
        try tree.refresh()
        var view = try SlackWindow.verify(destination, in: tree)
        let panes = view.window.all(Locators.secondaryView)
        if !panes.isEmpty {
            let pane = try view.window.one(Locators.secondaryView)
            let existing = try identify(pane, destination: destination)
            if existing.rootTs == rootTs { return existing }
            try close(pane, in: view, tree: tree, deadline: deadline, requireIdle: requireIdle)
            view = try SlackWindow.verify(destination, in: tree)
        }
        let target = MessageTarget(in: tree, deadline: deadline, requireIdle: requireIdle)
        _ = try target.openMenu(ts: rootTs, in: view)
        let result = Result {
            try requireIdle()
            try tree.refresh()
            let menu = try target.verifiedMenu(ts: rootTs, destination: destination)
            let control = try menu.one(Locators.openThread)
            guard Date() < deadline else { throw RemoteError.timeout }
            // An Accessibility error can follow a successful action. Observe the resulting pane.
            try? control.perform(.press)
            let thread = try Poll.until(deadline) {
                try tree.refresh()
                guard Overlays.open(in: tree).isEmpty else { return nil as VerifiedThread? }
                let fresh = try SlackWindow.verify(destination, in: tree)
                return try? verify(rootTs: rootTs, in: fresh)
            }
            guard let thread else { throw RemoteError.timeout }
            return thread
        }
        try target.closeMenuIfOpen()
        return try result.get()
    }

    public static func close(_ thread: VerifiedThread, in tree: SlackTree, deadline: Date,
                             requireIdle: () throws -> Void) throws {
        try tree.refresh()
        let view = try SlackWindow.verify(thread.destination, in: tree)
        let fresh = try verify(rootTs: thread.rootTs, in: view)
        try close(fresh.pane, in: view, tree: tree, deadline: deadline, requireIdle: requireIdle)
    }

    private static func close(_ pane: any UINode, in view: VerifiedView, tree: SlackTree, deadline: Date,
                              requireIdle: () throws -> Void) throws {
        let control = try pane.one(Locators.threadHeader).one(Locators.closeThread)
        try requireIdle()
        try Composer.requireLiveDestination(view)
        guard Date() < deadline else { throw RemoteError.timeout }
        try? control.perform(.press)
        let closed = try Poll.until(deadline) {
            try tree.refresh()
            let fresh = try SlackWindow.verify(view.destination, in: tree)
            return fresh.window.all(Locators.secondaryView).isEmpty ? true : nil
        }
        guard closed == true else { throw RemoteError.timeout }
    }
}

public enum MessageScope {
    case primary
    case thread(VerifiedThread)

    func node(in view: VerifiedView) throws -> any UINode {
        switch self {
        case .primary: return view.primaryView
        case .thread(let thread): return try verifiedThread(thread, in: view).pane
        }
    }

    func list(in view: VerifiedView) throws -> any UINode {
        switch self {
        case .primary: return try view.primaryView.one(Locators.messageList)
        case .thread(let thread): return try verifiedThread(thread, in: view).pane.one(Locators.threadList)
        }
    }

    var itemPrefix: String {
        switch self {
        case .primary: return "message-list_"
        case .thread(let thread): return thread.itemPrefix
        }
    }

    func timestamp(of node: any UINode) -> String? {
        guard Locators.virtualItem.matches(node), let id = node.domID, id.hasPrefix(itemPrefix) else { return nil }
        let ts = String(id.dropFirst(itemPrefix.count))
        return MessageReader.isTimestamp(ts) ? ts : nil
    }

    private func verifiedThread(_ thread: VerifiedThread, in view: VerifiedView) throws -> VerifiedThread {
        guard thread.destination == view.destination else {
            throw RemoteError.uiDrift(locator: "threadDestination", found: 0)
        }
        return try ThreadView.verify(rootTs: thread.rootTs, in: view)
    }
}
