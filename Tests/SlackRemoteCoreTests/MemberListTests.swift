@testable import SlackRemoteCore
import XCTest

final class MemberListTests: XCTestCase {
    func testMemberIDsOnlyAndClosesModal() throws {
        let fixture = try MemberModalFixture(rows: [
            DirectoryFixtures.memberRow("anchor_hack_item"),
            DirectoryFixtures.memberRow("U0EEEEEEE"),
            DirectoryFixtures.memberRow("W0FFFFFFF"),
            DirectoryFixtures.memberRow("add_member")
        ], tabTitle: "Members (2)")
        let result = try MemberList.read(DirectoryFixtures.destination, in: fixture.tree, bounds: DirectoryFixtures.bounds())
        XCTAssertEqual(result.listing.items.map(\.user.rawValue), ["U0EEEEEEE", "W0FFFFFFF"])
        XCTAssertEqual(result.listing.items.map(\.label), ["Ada Lovelace", "Ada Lovelace"])
        XCTAssertEqual(result.expectedCount, 2)
        XCTAssertTrue(result.listing.complete)
        XCTAssertFalse(fixture.isOpen)
        XCTAssertEqual(fixture.close.performCalls, [.press])
    }

    func testCountMismatchBecomesStalledButCallerLimitIsSuccess() {
        let shortfall = Paged<MemberList.Member>(items: [], pages: 2, stopReason: .endOfList)
        let result = MemberList.withCountCheck(shortfall, expected: 2)
        XCTAssertFalse(result.complete)
        XCTAssertEqual(result.stopReason, .stalled)
        XCTAssertThrowsError(try result.requireAllowed(allowPartial: false))

        let limited = Paged<MemberList.Member>(items: [], pages: 1, stopReason: .limit)
        XCTAssertEqual(MemberList.withCountCheck(limited, expected: 2).stopReason, .limit)
    }

    func testExpectedCountUsesFirstIntegerAndAcceptsLocalizedDigits() {
        XCTAssertEqual(MemberList.expectedCount(in: "Members ١٬٢٣٤ of 2,000"), 1_234)
        XCTAssertNil(MemberList.expectedCount(in: "Members"))
    }

    func testDMIsRefusedBeforePress() throws {
        let fixture = try MemberModalFixture(rows: [], tabTitle: nil)
        let dm = Destination(team: DirectoryFixtures.destination.team, conversation: ConversationID("D0CCCCCCC")!)
        XCTAssertThrowsError(try MemberList.read(dm, in: fixture.tree, bounds: DirectoryFixtures.bounds())) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "unsupported_destination")
        }
        XCTAssertEqual(fixture.opener.performCalls, [])
    }

    func testPagingErrorStillClosesTheModal() throws {
        let member = DirectoryFixtures.memberRow("U0EEEEEEE")
        member.onPerform = { _ in throw RemoteError.axFailure(operation: "AXScrollToVisible", code: -1) }
        let fixture = try MemberModalFixture(rows: [member], tabTitle: "Members (2)")
        XCTAssertThrowsError(try MemberList.read(DirectoryFixtures.destination, in: fixture.tree,
                                                 bounds: DirectoryFixtures.bounds())) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "ax_failure")
        }
        XCTAssertFalse(fixture.isOpen)
        XCTAssertEqual(fixture.close.performCalls, [.press])
    }
}
