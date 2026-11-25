import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct MessageTargetTests {
    @Test func findsTheExactRenderedID() throws {
        let fixture = try ComposerFixture()
        let match = MessageFixtures.message(0)
        fixture.list.children.append(contentsOf: [match, MessageFixtures.message(1)])
        let target = MessageTarget(in: fixture.tree, deadline: Date().addingTimeInterval(2), requireIdle: {})
        let item = try target.locate(ts: ThreadFixture.root, in: fixture.view, page: false)
        #expect((item as? FakeNode) === match)
        let error = #expect(throws: RemoteError.self) {
            try target.locate(ts: ThreadFixture.otherRoot, in: fixture.view, page: false)
        }
        #expect(error?.code == "message_not_rendered")
    }

    @Test func pagesTowardTheOlderItem() throws {
        let fixture = try ComposerFixture()
        let older = MessageFixtures.message(0)
        let newest = MessageFixtures.message(1)
        fixture.list.children.append(newest)
        newest.onPerform = { [weak fixture] action in
            if action == .scrollToVisible { fixture?.list.children.insert(older, at: 0) }
        }
        let target = MessageTarget(in: fixture.tree, deadline: Date().addingTimeInterval(2), requireIdle: {})
        let item = try target.locate(ts: ThreadFixture.root, in: fixture.view, page: true)
        #expect((item as? FakeNode) === older)
        #expect(newest.performCalls == [.scrollToVisible])
    }

    @Test func closesMenuForTheWrongMessage() throws {
        let fixture = try ComposerFixture()
        let selected = MessageFixtures.message(0)
        let wrong = MessageFixtures.message(1)
        fixture.list.children.append(contentsOf: [selected, wrong])
        let popup = MessagePopupFixture(webArea: fixture.webArea, item: selected, mark: wrong)
        let target = MessageTarget(in: fixture.tree, deadline: Date().addingTimeInterval(2), requireIdle: {})
        let error = #expect(throws: RemoteError.self) {
            try target.openMenu(ts: ThreadFixture.root, in: fixture.view)
        }
        #expect(error?.code == "ui_drift")
        #expect(popup.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }
}
