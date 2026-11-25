import Foundation

public enum StopReason: String, Encodable {
    case boundary
    case endOfList = "end_of_list"
    case limit
    case stalled
    case deadline
}

public struct PageBounds {
    public var maxItems: Int
    public var maxPages: Int
    public var deadline: Date

    public init(maxItems: Int, maxPages: Int, deadline: Date) {
        self.maxItems = maxItems
        self.maxPages = maxPages
        self.deadline = deadline
    }
}

public struct Paged<Item> {
    public let items: [Item]
    public let pages: Int
    public let stopReason: StopReason
    public var complete: Bool { stopReason == .boundary || stopReason == .endOfList }

    public func requireAllowed(allowPartial: Bool) throws {
        if !allowPartial && (stopReason == .stalled || stopReason == .deadline) {
            throw RemoteError.partialResult
        }
    }
}

public enum PageDirection { case towardStart, towardEnd }

public enum VirtualListPager {
    public static func collect<Key: Hashable, Item>(
        direction: PageDirection,
        bounds: PageBounds,
        rendered: () throws -> [(key: Key, node: any UINode, item: Item)],
        reachedBoundary: (Item) -> Bool,
        atEnd: () throws -> Bool
    ) throws -> Paged<Item> {
        var items: [Key: Item] = [:]
        var order: [Key] = []
        var pages = 0
        var emptyRounds = 0

        func result(_ reason: StopReason) -> Paged<Item> {
            Paged(items: order.compactMap { items[$0] }, pages: pages, stopReason: reason)
        }
        guard bounds.maxItems > 0, bounds.maxPages > 0 else { return result(.limit) }

        var rows = try rendered()
        while true {
            pages += 1
            var newKeys: Set<Key> = []
            var stop: StopReason?
            let traversal = direction == .towardStart ? Array(rows.reversed()) : rows
            for row in traversal where items[row.key] == nil {
                items[row.key] = row.item
                newKeys.insert(row.key)
                if reachedBoundary(row.item) {
                    stop = .boundary
                    break
                }
                if items.count == bounds.maxItems {
                    stop = .limit
                    break
                }
            }
            merge(rows.map(\.key), newKeys: newKeys, into: &order, direction: direction)
            if let stop { return result(stop) }
            if try atEnd() { return result(.endOfList) }
            if pages >= bounds.maxPages { return result(.limit) }
            if Date() >= bounds.deadline { return result(.deadline) }

            if pages > 1 { emptyRounds = newKeys.isEmpty ? emptyRounds + 1 : 0 }
            if emptyRounds == 3 { return result(.stalled) }

            let edge = direction == .towardStart ? rows.first : rows.last
            try edge?.node.perform(.scrollToVisible)
            let pollDeadline = min(bounds.deadline, Date().addingTimeInterval(1.5))
            if let next = try Poll.until(pollDeadline, {
                let snapshot = try rendered()
                rows = snapshot
                return snapshot.contains { items[$0.key] == nil } ? snapshot : nil
            }) {
                rows = next
            }
        }
    }

    /// Keep overlapping snapshots in list order. With no shared row, direction
    /// determines which end the newly rendered block belongs to.
    private static func merge<Key: Hashable>(_ snapshot: [Key], newKeys: Set<Key>,
                                             into order: inout [Key], direction: PageDirection) {
        guard !newKeys.isEmpty else { return }
        let existing = Set(order)
        var remaining = newKeys
        var pending: [Key] = []
        var before: [Key: [Key]] = [:]
        var previous: Key?
        for key in snapshot {
            if remaining.remove(key) != nil {
                pending.append(key)
            } else if existing.contains(key) {
                if !pending.isEmpty { before[key, default: []].append(contentsOf: pending) }
                pending.removeAll()
                previous = key
            }
        }
        var merged: [Key] = []
        if previous == nil && direction == .towardStart { merged.append(contentsOf: pending) }
        for key in order {
            merged.append(contentsOf: before[key] ?? [])
            merged.append(key)
            if key == previous { merged.append(contentsOf: pending) }
        }
        if previous == nil && direction == .towardEnd { merged.append(contentsOf: pending) }
        order = merged
    }
}
