@testable import SlackRemoteCore
import XCTest

final class DirectoryTests: XCTestCase {
    func testNamesWithoutStructuredIDsAreUnsupported() {
        let id = "U0AAAAAAA"
        let identified = FakeNode(role: "AXButton", domID: id)
        let labelOnly = FakeNode(role: "AXButton", attributes: [.title: .string(id)])

        XCTAssertThrowsError(try Directory.identifiedRows([identified, labelOnly]) { row in
            row.domID.flatMap(UserID.init(rawValue:))
        }) {
            XCTAssertEqual(($0 as? RemoteError)?.code, "unsupported_destination")
        }
    }
}
