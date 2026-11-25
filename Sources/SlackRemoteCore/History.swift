import Foundation

public enum History {
    public struct Snapshot {
        public let messages: [Message]
        public let pages: Int
        public let stopReason: StopReason
        public let complete: Bool
        public let skippedItems: Int
        public let scrollRestored: Bool
    }

    public static func read(_ destination: Destination, in tree: SlackTree, since: String?,
                            bounds: PageBounds, allowPartial: Bool, scope: MessageScope = .primary,
                            requireIdle: () throws -> Void = {}) throws -> Snapshot {
        var skipped: Set<String> = []

        func currentList() throws -> any UINode {
            try tree.refresh()
            let view: VerifiedView
            switch scope {
            case .primary: view = try SlackWindow.verifyForReading(destination, in: tree)
            case .thread: view = try SlackWindow.verify(destination, in: tree)
            }
            let list = try scope.list(in: view)
            try Composer.requireLiveDestination(view)
            try requireIdle()
            return list
        }

        let paged = try VirtualListPager.collect(direction: .towardStart, bounds: bounds, rendered: {
            let rendered = MessageReader.readList(try currentList(), scope: scope)
            skipped.formUnion(rendered.skipped)
            return rendered.rows
        }, reachedBoundary: { message in
            since.map { message.ts <= $0 } ?? false
        }, atEnd: { false })

        let ordered = paged.items.sorted { $0.ts < $1.ts }
        let newest = ordered.last?.ts
        let scrollRestored: Bool
        let list = try currentList()
        let endID: String
        switch scope {
        case .primary: endID = Locators.messageListBottomID
        case .thread(let thread): endID = thread.itemPrefix + "input"
        }
        let spacers = list.children.filter { $0.domID == endID }
        if let newest, spacers.count == 1, let spacer = spacers.first {
            try? spacer.perform(.scrollToVisible)
            let restored: Bool? = try Poll.until(min(bounds.deadline, Date().addingTimeInterval(2))) {
                let visible = MessageReader.readList(try currentList(), scope: scope).rows
                return visible.contains { $0.key == newest } ? true : nil
            }
            scrollRestored = restored == true
        } else {
            scrollRestored = false
        }
        try paged.requireAllowed(allowPartial: allowPartial)
        let messages = ordered.filter { message in since.map { message.ts > $0 } ?? true }
        return Snapshot(messages: messages, pages: paged.pages, stopReason: paged.stopReason,
                        complete: paged.complete, skippedItems: skipped.subtracting(ordered.map(\.ts)).count,
                        scrollRestored: scrollRestored)
    }
}
