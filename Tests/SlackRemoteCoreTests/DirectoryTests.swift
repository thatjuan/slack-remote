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

    func testDirectoryReturnClosesOnlyTheReopenedScopedSearch() throws {
        let fixture = try ChannelBrowserFixture()
        fixture.onReturn = { [unowned fixture] in
            fixture.showSearchPane()
            fixture.showUnrelatedPane()
        }
        try visitDirectory(fixture)

        let restored = try SlackWindow.verify(DirectoryFixtures.destination, in: fixture.tree)
        XCTAssertEqual(fixture.searchClose.performCalls, [.press])
        XCTAssertTrue(restored.window.all(Locators.scopedSearchHeader).isEmpty)
        XCTAssertEqual(restored.window.all(Locators.secondaryView).count, 1)
        XCTAssertTrue(fixture.unrelatedPane.performCalls.isEmpty)
    }

    func testDirectoryReturnPreservesAnExistingScopedSearch() throws {
        let fixture = try ChannelBrowserFixture()
        fixture.showSearchPane()
        fixture.onReturn = { [unowned fixture] in fixture.showSearchPane() }
        try visitDirectory(fixture)

        let restored = try SlackWindow.verify(DirectoryFixtures.destination, in: fixture.tree)
        XCTAssertEqual(restored.window.all(Locators.scopedSearchHeader).count, 1)
        XCTAssertTrue(fixture.searchClose.performCalls.isEmpty)
    }

    func testDirectoryReturnLeavesAnUnownedOrAmbiguousScopedSearchUntouched() throws {
        enum Scenario: String, CaseIterable {
            case paneBeforeReturn, duplicateHeader, userInput, differentAccount
        }
        for scenario in Scenario.allCases {
            let fixture = try ChannelBrowserFixture()
            fixture.onReturn = { [unowned fixture] in
                fixture.showSearchPane()
                if scenario == .duplicateHeader { fixture.showSearchPane() }
                if scenario == .differentAccount { fixture.changeSelfDM() }
            }
            XCTAssertThrowsError(try visitDirectory(fixture, secondsSinceUserInput: {
                scenario == .userInput ? 0 : .infinity
            }, beforeReturn: {
                if scenario == .paneBeforeReturn { fixture.showSearchPane() }
            }), scenario.rawValue) {
                XCTAssertEqual(($0 as? RemoteError)?.code, "overlay_left_open", scenario.rawValue)
            }
            XCTAssertTrue(fixture.searchClose.performCalls.isEmpty, scenario.rawValue)
        }
    }

    private func visitDirectory(_ fixture: ChannelBrowserFixture,
                                secondsSinceUserInput: () -> Double = { .infinity },
                                beforeReturn: () -> Void = {}) throws {
        try Directory.restoringConversation(in: fixture.tree, navigator: fixture.navigator(),
                                            directoryTeam: DirectoryFixtures.destination.team,
                                            secondsSinceUserInput: secondsSinceUserInput) {
            try Directory.openFromSidebar(in: fixture.tree, deadline: Date().addingTimeInterval(1))
            beforeReturn()
        }
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
