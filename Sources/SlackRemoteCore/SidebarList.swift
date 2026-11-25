import Foundation

public enum SidebarList {
    public struct Channel: Encodable {
        public enum Kind: String, Encodable {
            case channel, dm
            case groupDM = "group_dm"
            case selfDM = "self_dm"
        }

        public let conversation: ConversationID
        public let name: String
        public let kind: Kind
        public let selected: Bool
        public let hasDraft: Bool
    }

    public static func read(team: TeamID, in tree: SlackTree, bounds: PageBounds) throws -> Paged<Channel> {
        func currentList() throws -> any UINode {
            try tree.refresh()
            try Overlays.requireUnblocked(in: tree)
            let client = try SlackWindow.currentWindow(in: tree)
            guard client.location.team == team else { throw RemoteError.slackNotReady }
            return try client.window.one(Locators.sidebarList)
        }

        return try collect(bounds: bounds, currentList: currentList)
    }

    static func collect(bounds: PageBounds, currentList: () throws -> any UINode) throws -> Paged<Channel> {
        let initial = try currentList()
        let initialRows = initial.all(Locators.sidebarRow)
        let selected = initialRows.first {
            $0.domClasses.contains(Locators.sidebarRowSelected) && $0.domID.flatMap(ConversationID.init(rawValue:)) != nil
        }
        let anchor = selected ?? initialRows.first { $0.domID != nil }
        var anchorSeen = false
        var list = initial
        let result = Result {
            if let first = initialRows.first {
                try first.perform(.scrollToVisible)
            }
            return try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: {
                list = try currentList()
                let rows = list.all(Locators.sidebarRow)
                if let id = anchor?.domID, rows.contains(where: { $0.domID == id }) { anchorSeen = true }
                return rows.compactMap { row in
                    channel(in: row).map { ($0.conversation, row, $0) }
                }
            }, reachedBoundary: { _ in false }, atEnd: {
                list.descendants().contains { $0.domID == Locators.sidebarEndID }
            })
        }
        if let anchor, let id = anchor.domID {
            try restore(anchor, id: id, direction: anchorSeen ? .towardStart : .towardEnd, currentList: currentList)
        }
        return try result.get()
    }

    private static func restore(_ anchor: any UINode, id: String, direction: PageDirection,
                                currentList: () throws -> any UINode) throws {
        func visibleAnchor() throws -> (any UINode)? {
            try currentList().all(Locators.sidebarRow).first { $0.domID == id }
        }
        if let visible = try visibleAnchor() {
            try visible.perform(.scrollToVisible)
            return
        }
        if (try? anchor.perform(.scrollToVisible)) != nil, try visibleAnchor() != nil { return }

        // Virtualization can invalidate the saved node. Find the same row in a fresh snapshot.
        let cleanup = PageBounds(maxItems: .max, maxPages: 100, deadline: Date().addingTimeInterval(5))
        _ = try VirtualListPager.collect(direction: direction, bounds: cleanup, rendered: {
            try currentList().all(Locators.sidebarRow).compactMap { row in
                row.domID.map { (key: $0, node: row, item: $0) }
            }
        }, reachedBoundary: { $0 == id }, atEnd: { false })
        guard let visible = try visibleAnchor() else {
            throw RemoteError.uiDrift(locator: "sidebarScrollAnchor", found: 0)
        }
        try visible.perform(.scrollToVisible)
    }

    static func channel(in row: any UINode) -> Channel? {
        guard let raw = row.domID, let id = ConversationID(raw) else { return nil }
        let group = row.all(Locators.sidebarRowTarget).first
        let classes = Set(row.domClasses + (group?.domClasses ?? []))
        let kind: Channel.Kind
        if classes.contains(Locators.selfDM) && id.kind == .directMessage {
            kind = .selfDM
        } else if classes.contains(Locators.sidebarGroupDM) && id.kind != .channel {
            kind = .groupDM
        } else {
            kind = id.kind == .directMessage ? .dm : .channel
        }
        let text = row.descendants().filter { $0.role == "AXStaticText" }.compactMap {
            $0.string(.value) ?? $0.string(.title)
        }
        let name = text.flatMap { $0.split(whereSeparator: \.isWhitespace) }.joined(separator: " ")
        return Channel(conversation: id, name: name, kind: kind,
                       selected: classes.contains(Locators.sidebarRowSelected),
                       hasDraft: classes.contains(Locators.sidebarDraft))
    }
}
