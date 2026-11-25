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
        var initialAnchor: String?
        var capturedAnchor = false

        func currentList() throws -> any UINode {
            try tree.refresh()
            let view = try SlackWindow.verify(destination, in: tree)
            let list = try scope.list(in: view)
            try Composer.requireLiveDestination(view)
            try requireIdle()
            return list
        }

        // Leave time for the reverse scroll even when collection reaches its deadline.
        let restorationWindow: TimeInterval = 5
        let reserve = min(restorationWindow, max(0, bounds.deadline.timeIntervalSinceNow) / 3)
        var readBounds = bounds
        readBounds.deadline = bounds.deadline.addingTimeInterval(-reserve)

        func restore(pagedAway: Bool) throws -> Bool {
            try restoreAnchor(initialAnchor, pagedAway: pagedAway, scope: scope,
                              deadline: min(bounds.deadline, Date().addingTimeInterval(restorationWindow)),
                              currentList: currentList)
        }

        let paged: Paged<Message>
        do {
            paged = try VirtualListPager.collect(direction: .towardStart, bounds: readBounds, rendered: {
                let list = try currentList()
                if !capturedAnchor {
                    initialAnchor = list.children.reversed().lazy.compactMap(scope.timestamp(of:)).first
                    capturedAnchor = true
                }
                let rendered = MessageReader.readList(list, scope: scope)
                skipped.formUnion(rendered.skipped)
                return rendered.rows
            }, reachedBoundary: { message in
                since.map { message.ts <= $0 } ?? false
            }, atEnd: { false })
            try paged.requireAllowed(allowPartial: allowPartial)
        } catch {
            if initialAnchor != nil { _ = try? restore(pagedAway: true) }
            throw error
        }

        let scrollRestored = try restore(pagedAway: paged.pages > 1)
        let ordered = paged.items.sorted { $0.ts < $1.ts }
        let messages = ordered.filter { message in since.map { message.ts > $0 } ?? true }
        return Snapshot(messages: messages, pages: paged.pages, stopReason: paged.stopReason,
                        complete: paged.complete, skippedItems: skipped.subtracting(ordered.map(\.ts)).count,
                        scrollRestored: scrollRestored)
    }

    private static func restoreAnchor(_ anchor: String?, pagedAway: Bool, scope: MessageScope, deadline: Date,
                                      currentList: () throws -> any UINode) throws -> Bool {
        func rendered() throws -> [(key: String, node: any UINode, item: String)] {
            try currentList().children.compactMap { node in
                scope.timestamp(of: node).map { ($0, node, $0) }
            }
        }

        var rows = try rendered()
        guard let anchor else { return false }
        if !pagedAway { return rows.filter { $0.key == anchor }.count == 1 }
        guard Date() < deadline else { return false }

        do {
            if !rows.contains(where: { $0.key == anchor }) {
                // The original AX row may have been virtualized away. Stop if we reach or pass its timestamp.
                _ = try VirtualListPager.collect(direction: .towardEnd,
                    bounds: .init(maxItems: .max, maxPages: 20, deadline: deadline), rendered: rendered,
                    reachedBoundary: { $0 >= anchor }, atEnd: { false })
                rows = try rendered()
            }

            let matches = rows.filter { $0.key == anchor }
            guard matches.count == 1, let row = matches.first, Date() < deadline else { return false }
            try row.node.perform(.scrollToVisible)
        } catch RemoteError.axFailure(let operation, _) where operation == UIAction.scrollToVisible.rawValue {
            _ = try currentList()
            return false
        }
        return try Poll.until(deadline) {
            try rendered().filter { $0.key == anchor }.count == 1 ? true : nil
        } == true
    }
}
