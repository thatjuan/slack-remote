@testable import SlackRemoteCore
import XCTest

final class DirectoryTests: XCTestCase {
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
