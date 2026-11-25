@testable import SlackRemoteCore
import XCTest

final class SidebarListTests: XCTestCase {
    func testKindsAndFlagsComeFromIDsAndClasses() throws {
        let samples: [(String, [String], SidebarList.Channel.Kind)] = [
            ("C0BBBBBBB", [], .channel),
            ("G0BBBBBBB", [], .channel),
            ("G0CCCCCCC", [Locators.sidebarGroupDM], .groupDM),
            ("D0BBBBBBB", [], .dm),
            ("D0CCCCCCC", [Locators.selfDM], .selfDM)
        ]
        for (id, classes, kind) in samples {
            let row = DirectoryFixtures.sidebarRow(id, name: "  Project\n  Team ",
                                                   classes: classes + [Locators.sidebarDraft], selected: true)
            let item = try XCTUnwrap(SidebarList.channel(in: row))
            XCTAssertEqual(item.conversation.rawValue, id)
            XCTAssertEqual(item.kind, kind)
            XCTAssertEqual(item.name, "Project Team")
            XCTAssertTrue(item.selected)
            XCTAssertTrue(item.hasDraft)
        }
        XCTAssertNil(SidebarList.channel(in: DirectoryFixtures.sidebarRow(nil)))
        XCTAssertNil(SidebarList.channel(in: DirectoryFixtures.sidebarRow(Locators.sidebarEndID)))
    }

    func testPagingKeepsRowsThatLeaveTheTreeAndRestoresSelection() throws {
        let first = DirectoryFixtures.sidebarRow("C0AAAAAAA")
        let selected = DirectoryFixtures.sidebarRow("C0BBBBBBB", selected: true)
        let newest = DirectoryFixtures.sidebarRow("C0CCCCCCC")
        let end = DirectoryFixtures.sidebarRow(Locators.sidebarEndID)
        let list = FakeNode(role: "AXOutline", children: [first, selected])
        var paged = false
        selected.onPerform = { action in
            XCTAssertEqual(action, .scrollToVisible)
            list.children = paged ? [first, selected] : [newest, end]
            paged = true
        }
        let result = try SidebarList.collect(bounds: DirectoryFixtures.bounds()) { list }
        XCTAssertEqual(result.items.map(\.conversation.rawValue), ["C0AAAAAAA", "C0BBBBBBB", "C0CCCCCCC"])
        XCTAssertEqual(result.stopReason, .endOfList)
        XCTAssertEqual(result.pages, 2)
        XCTAssertEqual(selected.performCalls, [.scrollToVisible, .scrollToVisible])
    }

    func testMaxItemsStopsAtLimit() throws {
        let first = DirectoryFixtures.sidebarRow("C0AAAAAAA")
        let second = DirectoryFixtures.sidebarRow("C0BBBBBBB")
        let list = FakeNode(role: "AXOutline", children: [first, second])
        let result = try SidebarList.collect(bounds: DirectoryFixtures.bounds(items: 1)) { list }
        XCTAssertEqual(result.items.map(\.conversation.rawValue), ["C0AAAAAAA"])
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.stopReason, .limit)
        XCTAssertEqual(second.performCalls, [])
    }

    func testScrollRestorationReacquiresARecycledSelectedRow() throws {
        let first = DirectoryFixtures.sidebarRow("C0AAAAAAA")
        let selected = DirectoryFixtures.sidebarRow("C0BBBBBBB", selected: true)
        let replacement = DirectoryFixtures.sidebarRow("C0BBBBBBB", selected: true)
        let next = DirectoryFixtures.sidebarRow("C0CCCCCCC")
        let end = DirectoryFixtures.sidebarRow(Locators.sidebarEndID)
        let list = FakeNode(role: "AXOutline", children: [first, selected])
        selected.onPerform = { _ in
            guard list.children.contains(where: { $0.domID == selected.domID }) else {
                throw RemoteError.axFailure(operation: "AXScrollToVisible", code: -1)
            }
            list.children = [next, end]
        }
        next.onPerform = { _ in list.children = [first, replacement] }

        let result = try SidebarList.collect(bounds: DirectoryFixtures.bounds()) { list }
        XCTAssertTrue(result.complete)
        XCTAssertEqual(replacement.performCalls, [.scrollToVisible])
    }
}
