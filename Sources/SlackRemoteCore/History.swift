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
                            bounds: PageBounds, allowPartial: Bool) throws -> Snapshot {
        var skipped: Set<String> = []

        func currentList() throws -> any UINode {
            try tree.refresh()
            let view = try SlackWindow.verify(destination, in: tree)
            let list = try view.primaryView.one(Locators.messageList)
            try Composer.requireLiveDestination(view)
            return list
        }

        let paged = try VirtualListPager.collect(direction: .towardStart, bounds: bounds, rendered: {
            let rendered = MessageReader.readList(try currentList())
            skipped.formUnion(rendered.skipped)
            return rendered.rows
        }, reachedBoundary: { message in
            since.map { message.ts <= $0 } ?? false
        }, atEnd: { false })

        let ordered = paged.items.sorted { $0.ts < $1.ts }
        let newest = ordered.last?.ts
        let scrollRestored: Bool
        let list = try currentList()
        let spacers = list.children.filter { $0.domID == Locators.messageListBottomID }
        if let newest, spacers.count == 1, let spacer = spacers.first {
            try? spacer.perform(.scrollToVisible)
            let restored: Bool? = try Poll.until(Date().addingTimeInterval(2)) {
                let visible = MessageReader.readList(try currentList()).rows
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
