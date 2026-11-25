import SlackRemoteCore

final class PagingFixture {
    private let snapshots: [[(key: Int, node: any UINode, item: Int)]]
    private(set) var moves = 0
    private(set) var index = 0

    init(_ keys: [[Int]], direction: PageDirection) {
        snapshots = keys.map { values in
            values.map { (key: $0, node: FakeNode(role: "AXRow"), item: $0) }
        }
        for rows in snapshots {
            let edge = direction == .towardStart ? rows.first : rows.last
            (edge?.node as? FakeNode)?.onPerform = { [weak self] action in
                guard let self, action == .scrollToVisible else { return }
                moves += 1
                index = min(index + 1, snapshots.count - 1)
            }
        }
    }

    func rendered() -> [(key: Int, node: any UINode, item: Int)] { snapshots[index] }
}
