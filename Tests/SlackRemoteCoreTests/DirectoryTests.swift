@testable import SlackRemoteCore
import Foundation
import XCTest

final class DirectoryTests: XCTestCase {
    func testBrowseChannelsClosesItsMenuWhileDirectoryReplacesConversation() throws {
        let fixture = try ChannelBrowserFixture()
        let destination = DirectoryFixtures.destination
        let listing = try Directory.restoringConversation(in: fixture.tree, navigator: fixture.navigator()) {
            try Directory.openFromSidebar(in: fixture.tree, deadline: Date().addingTimeInterval(1))
            let client = try SlackWindow.currentWindow(in: fixture.tree)
            XCTAssertEqual(client.location, .other(team: destination.team, path: []))
            XCTAssertTrue(Overlays.open(in: fixture.tree).isEmpty)
            XCTAssertTrue(fixture.backdrop.performCalls.isEmpty)
            let bounds = PageBounds(maxItems: 10, maxPages: 10, deadline: Date().addingTimeInterval(0.1))
            return try Directory.readChannels(team: destination.team, in: fixture.tree, bounds: bounds)
        }
        XCTAssertEqual(listing.items.map(\.name), ["General", "Notes"])
        XCTAssertEqual(listing.stopReason, .deadline)
        XCTAssertFalse(listing.complete)
        XCTAssertEqual(fixture.links, [destination.channelLink])
        _ = try SlackWindow.verify(destination, in: fixture.tree)
    }

    func testBrowseChannelsPreservesReplacementOverlay() throws {
        let fixture = try ChannelBrowserFixture()
        fixture.browse.onPerform = { _ in fixture.replaceMenu() }
        XCTAssertThrowsError(try Directory.openFromSidebar(in: fixture.tree, deadline: Date().addingTimeInterval(1))) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "overlay_left_open")
        }
        XCTAssertEqual(Overlays.open(in: fixture.tree), [.modal])
        XCTAssertTrue(fixture.backdrop.performCalls.isEmpty)
        XCTAssertTrue(fixture.replacement.performCalls.isEmpty)
    }

    func testBrowseChannelsDismissesItsOwnMenuAfterPressFails() throws {
        let fixture = try ChannelBrowserFixture()
        fixture.browse.onPerform = { _ in throw RemoteError.axFailure(operation: "AXPress", code: -1) }
        XCTAssertThrowsError(try Directory.openFromSidebar(in: fixture.tree, deadline: Date().addingTimeInterval(1))) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "ax_failure")
        }
        XCTAssertEqual(fixture.backdrop.performCalls, [.press])
        _ = try SlackWindow.verify(DirectoryFixtures.destination, in: fixture.tree)
    }

    func testNamesWithoutStructuredIDsAreUnsupported() {
        let id = "U0AAAAAAA"
        let identified = cell(infoID: Locators.directoryPersonIDPrefix + id)
        let labelOnly = cell(infoID: nil)
        XCTAssertThrowsError(try Directory.peopleRows([identified, labelOnly])) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "unsupported_destination")
        }
    }

    func testDirectoryUsesTheStructuredUserIDAndVisibleLabel() throws {
        let id = "U0AAAAAAA"
        let items = try Directory.peopleRows([cell(infoID: Locators.directoryPersonIDPrefix + id)])
        XCTAssertEqual(items.map(\.key.rawValue), [id])
        XCTAssertEqual(items.map(\.item.label), ["Example Person"])
    }

    private func cell(infoID: String?) -> FakeNode {
        let text = FakeNode(role: "AXStaticText", attributes: [.value: .string("Example Person")])
        let info = FakeNode(role: "AXGroup", domClasses: Locators.directoryPersonInfo.classes,
                            domID: infoID, children: [text])
        return FakeNode(role: "AXCell", domClasses: Locators.directoryPersonCell.classes, children: [info])
    }
}
