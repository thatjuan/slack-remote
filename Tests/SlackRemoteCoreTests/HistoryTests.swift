import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct HistoryTests {
    @Test func mergesVirtualizedMessagesAndRestoresTheInitialAnchorAcrossPages() throws {
        let fixture = try ComposerFixture()
        let bottom = MessageFixtures.spacer()
        let initial = [MessageFixtures.message(5), MessageFixtures.message(6)]
        let middle = [MessageFixtures.message(3), MessageFixtures.message(4)]
        let earlier = [MessageFixtures.message(1), MessageFixtures.message(2)]
        let newer = MessageFixtures.message(7)
        fixture.list.children = initial
        initial[0].onPerform = { _ in fixture.list.children = middle }
        middle[0].onPerform = { _ in fixture.list.children = earlier }
        earlier[1].onPerform = { _ in fixture.list.children = middle }
        middle[1].onPerform = { _ in fixture.list.children = initial + [newer, bottom] }

        let history = try History.read(fixture.view.destination, in: fixture.tree, since: "1700000001.000100",
            bounds: .init(maxItems: 20, maxPages: 3, deadline: Date().addingTimeInterval(5)), allowPartial: false)
        #expect(history.messages.map(\.ts) == (2...6).map { "170000000\($0).000100" })
        #expect(history.stopReason == .boundary)
        #expect(history.complete)
        #expect(history.pages == 3)
        #expect(history.scrollRestored)
        #expect(earlier[1].performCalls == [.scrollToVisible])
        #expect(middle[1].performCalls == [.scrollToVisible])
        #expect(initial[1].performCalls == [.scrollToVisible])
        #expect(newer.performCalls.isEmpty)
        #expect(bottom.performCalls.isEmpty)
    }

    @Test func onePageVerifiesTheAnchorWithoutScrolling() throws {
        let fixture = try ComposerFixture()
        let anchor = MessageFixtures.message(2)
        fixture.list.children = [anchor]

        let history = try History.read(fixture.view.destination, in: fixture.tree, since: nil,
            bounds: .init(maxItems: 20, maxPages: 1, deadline: .distantFuture), allowPartial: false)
        #expect(history.stopReason == .limit)
        #expect(history.pages == 1)
        #expect(history.scrollRestored)
        #expect(anchor.performCalls.isEmpty)
    }

    @Test func stalledRestorationReportsFalseAndKeepsTheHistoryLimit() throws {
        let fixture = try ComposerFixture()
        let bottom = MessageFixtures.spacer()
        let initial = [MessageFixtures.message(3), MessageFixtures.message(4), bottom]
        let earlier = [MessageFixtures.message(1), MessageFixtures.message(2)]
        fixture.list.children = initial
        initial[0].onPerform = { _ in fixture.list.children = earlier }

        let history = try History.read(fixture.view.destination, in: fixture.tree, since: nil,
            bounds: .init(maxItems: 20, maxPages: 2, deadline: Date().addingTimeInterval(8)), allowPartial: false)
        #expect(history.messages.count == 4)
        #expect(history.stopReason == .limit)
        #expect(history.pages == 2)
        #expect(!history.complete)
        #expect(!history.scrollRestored)
        #expect(earlier[1].performCalls == Array(repeating: .scrollToVisible, count: 3))
        #expect(bottom.performCalls.isEmpty)
    }

    @Test func stalledHistoryRequiresOptInAndStillRestores() throws {
        let fixture = try ComposerFixture()
        let anchor = MessageFixtures.message(1)
        fixture.list.children = [anchor]
        let error = #expect(throws: RemoteError.self) {
            try History.read(fixture.view.destination, in: fixture.tree, since: nil,
                bounds: .init(maxItems: 20, maxPages: 20, deadline: Date().addingTimeInterval(10)), allowPartial: false)
        }
        #expect(error?.code == "partial_result")
        #expect(error?.exitStatus == 19)
        #expect(anchor.performCalls == Array(repeating: .scrollToVisible, count: 4))
    }

    @Test func deadlineLeavesTimeToRestoreAnAnchorDroppedDuringPaging() throws {
        let fixture = try ComposerFixture()
        let initial = [MessageFixtures.message(3), MessageFixtures.message(4)]
        let earlier = [MessageFixtures.message(1), MessageFixtures.message(2)]
        fixture.list.children = initial
        initial[0].onPerform = { _ in fixture.list.children = earlier }
        earlier[1].onPerform = { _ in fixture.list.children = initial }

        let history = try History.read(fixture.view.destination, in: fixture.tree, since: nil,
            bounds: .init(maxItems: 20, maxPages: 20, deadline: Date().addingTimeInterval(2)), allowPartial: true)
        #expect(history.messages.count == 4)
        #expect(!history.complete)
        #expect(history.stopReason == .deadline)
        #expect(history.scrollRestored)
        #expect(initial[1].performCalls == [.scrollToVisible])
    }

    @Test func aCleanupFailurePreservesTheOriginalPagingError() throws {
        let fixture = try ComposerFixture()
        let initial = MessageFixtures.message(4)
        let earlier = MessageFixtures.message(2)
        fixture.list.children = [initial]
        initial.onPerform = { _ in
            fixture.list.children = [earlier]
            throw RemoteError.slackInUse
        }
        earlier.onPerform = { _ in
            throw RemoteError.axFailure(operation: UIAction.scrollToVisible.rawValue, code: -1)
        }

        let error = #expect(throws: RemoteError.self) {
            try History.read(fixture.view.destination, in: fixture.tree, since: nil,
                bounds: .init(maxItems: 20, maxPages: 5, deadline: .distantFuture), allowPartial: true)
        }
        #expect(error?.code == "slack_in_use")
        #expect(earlier.performCalls == [.scrollToVisible])
    }

    @Test func aThreadChangeDuringRestorationFailsVerification() throws {
        let fixture = try ThreadFixture()
        let differentThread = try ThreadFixture(root: ThreadFixture.otherRoot)
        fixture.appendReply("synthetic")
        let thread = try fixture.verify()
        let root = try #require(fixture.list.children.first as? FakeNode)
        let reply = try #require(fixture.list.children[1] as? FakeNode)
        let anchor = MessageFixtures.message(2)
        anchor.domID = thread.itemPrefix + "1700000002.000100"
        let initial = [reply, anchor, fixture.list.children[2]]
        fixture.list.children = initial
        reply.onPerform = { _ in fixture.list.children = [root] }
        root.onPerform = { _ in fixture.list.children = initial }
        anchor.onPerform = { _ in fixture.pane.children = differentThread.pane.children }

        let error = #expect(throws: RemoteError.self) {
            try History.read(thread.destination, in: fixture.primary.tree, since: nil,
                bounds: .init(maxItems: 20, maxPages: 2, deadline: .distantFuture), allowPartial: true,
                scope: .thread(thread))
        }
        #expect(error?.code == "ui_drift")
        #expect(anchor.performCalls == [.scrollToVisible])
        #expect(fixture.close.performCalls.isEmpty)
    }

    @Test func deadlineReportsAvailableMessagesWhenPartialResultsAreAllowed() throws {
        let fixture = try ComposerFixture()
        fixture.appendMessage(1, text: "synthetic")
        let history = try History.read(fixture.view.destination, in: fixture.tree, since: nil,
            bounds: .init(maxItems: 20, maxPages: 20, deadline: .distantPast), allowPartial: true)
        #expect(history.messages.count == 1)
        #expect(!history.complete)
        #expect(history.stopReason == .deadline)
    }
}
