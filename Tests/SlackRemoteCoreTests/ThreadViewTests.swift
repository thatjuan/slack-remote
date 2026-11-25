import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct ThreadViewTests {
    @Test func verifiesAndReadsTheRootAndRepliesInOrder() throws {
        let fixture = try ThreadFixture()
        fixture.appendReply("synthetic reply")
        let thread = try fixture.verify()
        let rendered = try MessageReader.read(fixture.primary.view, scope: .thread(thread), limit: nil)
        #expect(rendered.messages.map(\.ts) == [ThreadFixture.root, ThreadFixture.reply])
        #expect(rendered.messages.map(\.text) == ["synthetic root", "synthetic reply"])
    }

    @Test func rejectsWrongRootAndConversation() throws {
        let fixture = try ThreadFixture()
        #expect(throws: RemoteError.self) { try fixture.verify(root: ThreadFixture.otherRoot) }
        let row = try #require(fixture.list.children.first as? FakeNode)
        row.domID = "D0CCCCCCC-\(ThreadFixture.root)-thread-list-Thread_\(ThreadFixture.root)"
        #expect(throws: RemoteError.self) { try fixture.verify() }
    }

    @Test func rejectsComposerWithoutAnyThreadMessages() throws {
        let fixture = try ThreadFixture()
        fixture.list.children.removeFirst()
        #expect(throws: RemoteError.self) { try fixture.verify() }
    }

    @Test func willNotCloseAPaneWithAnUnverifiedThreadIdentity() throws {
        let fixture = try ThreadFixture()
        let row = try #require(fixture.list.children.first as? FakeNode)
        row.domID = "D0CCCCCCC-\(ThreadFixture.root)-thread-list-Thread_\(ThreadFixture.root)"
        let error = #expect(throws: RemoteError.self) {
            try ThreadView.open(fixture.primary.view.destination, rootTs: ThreadFixture.otherRoot,
                in: fixture.primary.tree, deadline: Date().addingTimeInterval(2), requireIdle: {})
        }
        #expect(error?.code == "ui_drift")
        #expect(fixture.close.performCalls.isEmpty)
    }

    @Test func opensADifferentThreadViaItsExactMenu() throws {
        let fixture = try ThreadFixture()
        let other = try ThreadFixture(root: ThreadFixture.otherRoot)
        let parent = MessageFixtures.message(10)
        fixture.primary.list.children.append(parent)
        let popup = MessagePopupFixture(webArea: fixture.primary.webArea, item: parent)
        let open = FakeNode(role: "AXMenuItem", domClasses: Locators.openThread.classes)
        open.onPerform = { [weak popup, weak fixture, weak other] _ in
            popup?.dismiss()
            if let other { fixture?.primary.webArea.children.append(other.pane) }
        }
        popup.menu.children = [open]
        let thread = try ThreadView.open(fixture.primary.view.destination, rootTs: ThreadFixture.otherRoot,
                                         in: fixture.primary.tree, deadline: Date().addingTimeInterval(2), requireIdle: {})
        #expect(thread.rootTs == ThreadFixture.otherRoot)
        #expect(fixture.close.performCalls == [.press])
        #expect(parent.performCalls == [.showMenu])
        #expect(open.performCalls == [.press])
        #expect(Overlays.open(in: fixture.primary.tree).isEmpty)
    }

    @Test func sendsOnceFromTheThreadComposer() throws {
        let fixture = try ThreadFixture()
        fixture.scriptSend("synthetic reply")
        let receipt = try fixture.sender().send("synthetic reply", deadline: Date().addingTimeInterval(2))
        #expect(receipt.ts == ThreadFixture.reply)
        #expect(fixture.threadComposer.send.performCalls == [.press])
        #expect(fixture.primary.send.performCalls.isEmpty)
        #expect(fixture.broadcast.performCalls.isEmpty)
    }

    @Test func rootDriftPreventsSending() throws {
        let fixture = try ThreadFixture()
        let sender = try fixture.sender {
            (fixture.list.children.first as? FakeNode)?.domID = "replaced"
        }
        let error = #expect(throws: WriteFailure.self) {
            try sender.send("synthetic reply", deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "ui_drift")
        #expect(fixture.threadComposer.send.performCalls.isEmpty)
        #expect(fixture.primary.send.performCalls.isEmpty)
    }

    @Test func unchecksBroadcastBeforeSending() throws {
        let fixture = try ThreadFixture()
        fixture.broadcast.attributes[.value] = .bool(true)
        fixture.broadcast.onPerform = { [weak fixture] _ in fixture?.broadcast.attributes[.value] = .bool(false) }
        fixture.scriptSend("synthetic reply")
        let press = fixture.threadComposer.send.onPerform
        fixture.threadComposer.send.onPerform = { [weak fixture] action in
            #expect(fixture?.broadcast.bool(.value) == false)
            try press?(action)
        }
        _ = try fixture.sender().send("synthetic reply", deadline: Date().addingTimeInterval(2))
        #expect(fixture.broadcast.performCalls == [.press])
        #expect(fixture.threadComposer.send.performCalls == [.press])
    }

    @Test func unchangedBroadcastLeavesDraftAndPreventsSending() throws {
        let fixture = try ThreadFixture()
        fixture.broadcast.attributes[.value] = .bool(true)
        let error = #expect(throws: WriteFailure.self) {
            try fixture.sender().send("synthetic reply", deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "write_unverified")
        #expect(error?.draftLeft == true)
        #expect(fixture.broadcast.performCalls == [.press])
        #expect(fixture.threadComposer.send.performCalls.isEmpty)
    }
}
