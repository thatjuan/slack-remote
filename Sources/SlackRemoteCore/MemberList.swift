import Foundation

public enum MemberList {
    public struct Member: Encodable {
        public let user: UserID
        public let label: String
    }

    public struct Snapshot {
        public let listing: Paged<Member>
        public let expectedCount: Int?
    }

    public static func requireSupported(_ destination: Destination) throws {
        guard destination.conversation.kind != .directMessage else { throw RemoteError.unsupportedDestination }
    }

    public static func read(_ destination: Destination, in tree: SlackTree, bounds: PageBounds) throws -> Snapshot {
        try requireSupported(destination)
        let snapshot = try Overlays.withModal(in: tree, deadline: bounds.deadline, opening: {
            let view = try SlackWindow.verify(destination, in: tree)
            let header = try view.primaryView.one(Locators.conversationHeader)
            guard let button = header.all(Locators.memberDetails).first else {
                throw RemoteError.uiDrift(locator: Locators.memberDetails.name, found: 0)
            }
            guard Date() < bounds.deadline else { throw RemoteError.timeout }
            try button.perform(.press)
        }) { _ in
            let result = Result { try collect(in: tree, bounds: bounds) }
            // Let the shared overlay owner verify dismissal and try the backdrop if needed.
            if let modal = try? currentModal(in: tree), let close = try? modal.one(Locators.aboutClose) {
                try? close.perform(.press)
                _ = try? Poll.until(Date().addingTimeInterval(1)) {
                    try tree.refresh()
                    return Overlays.open(in: tree).isEmpty ? true : nil
                }
            }
            return try result.get()
        }
        _ = try SlackWindow.verify(destination, in: tree)
        return snapshot
    }

    private static func currentModal(in tree: SlackTree) throws -> any UINode {
        try tree.refresh()
        let window = try SlackWindow.currentWindow(in: tree).window
        return try window.one(Locators.aboutModal)
    }

    private static func tab(in modal: any UINode) throws -> any UINode {
        let tabs = modal.all(Locators.membersTab).filter { $0.domID == "members" }
        guard tabs.count == 1, let tab = tabs.first else {
            throw RemoteError.uiDrift(locator: Locators.membersTab.name, found: tabs.count)
        }
        return tab
    }

    private static func collect(in tree: SlackTree, bounds: PageBounds) throws -> Snapshot {
        var modal = try currentModal(in: tree)
        var membersTab = try tab(in: modal)
        if membersTab.bool(.value) != true {
            try membersTab.perform(.press)
            let selection = try Poll.until(bounds.deadline) {
                modal = try currentModal(in: tree)
                let candidate = try tab(in: modal)
                return candidate.bool(.value) == true ? candidate : nil
            }
            guard let selection else { throw RemoteError.timeout }
            membersTab = selection
        }
        let expected = expectedCount(in: membersTab.string(.title) ?? membersTab.string(.description))
        var seen: Set<UserID> = []
        func rendered() throws -> [(key: UserID, node: any UINode, item: Member)] {
            modal = try currentModal(in: tree)
            return try modal.all(Locators.memberRow).compactMap { row in
                guard let raw = row.domID, let user = UserID(raw) else { return nil }
                let label = try row.one(Locators.memberLabel).string(.title) ?? ""
                seen.insert(user)
                return (user, row, Member(user: user, label: label))
            }
        }
        let paged = try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: rendered,
                                                 reachedBoundary: { _ in false }, atEnd: {
            expected.map { seen.count >= $0 } ?? false
        })
        return Snapshot(listing: withCountCheck(paged, expected: expected), expectedCount: expected)
    }

    static func withCountCheck(_ listing: Paged<Member>, expected: Int?) -> Paged<Member> {
        guard let expected, listing.stopReason != .limit, listing.items.count != expected else { return listing }
        return Paged(items: listing.items, pages: listing.pages, stopReason: .stalled)
    }

    static func expectedCount(in title: String?) -> Int? {
        guard let title else { return nil }
        let pattern = #/\p{Nd}{1,3}(?:[,.\u{00A0}\u{066C}\u{202F}]\p{Nd}{3})+|\p{Nd}+/#
        guard let match = title.firstMatch(of: pattern) else { return nil }
        return Int(match.output.compactMap(\.wholeNumberValue).map(String.init).joined())
    }
}
