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
        let selected = initial.all(Locators.sidebarRow).first {
            $0.domClasses.contains(Locators.sidebarRowSelected) && $0.domID.flatMap(ConversationID.init(rawValue:)) != nil
        }
        var moved = false
        var list = initial
        let result = Result {
            if let first = initial.all(Locators.sidebarRow).first {
                moved = true
                try first.perform(.scrollToVisible)
            }
            return try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: {
                list = try currentList()
                return list.all(Locators.sidebarRow).compactMap { row in
                    channel(in: row).map { ($0.conversation, row, $0) }
                }
            }, reachedBoundary: { _ in false }, atEnd: {
                list.descendants().contains { $0.domID == Locators.sidebarEndID }
            })
        }
        if moved, let selected {
            let current = try currentList()
            let live = current.all(Locators.sidebarRow).first { $0.domID == selected.domID }
            try (live ?? selected).perform(.scrollToVisible)
        }
        return try result.get()
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
