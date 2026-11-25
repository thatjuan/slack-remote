import Foundation
import SlackRemoteCore
import Testing

@MainActor
struct HistoryTests {
    @Test func mergesVirtualizedMessagesTrimsSinceAndRestoresBottom() throws {
        let fixture = try ComposerFixture()
        let bottom = MessageFixtures.spacer()
        let latest = [MessageFixtures.message(3), MessageFixtures.message(4), bottom]
        let earlier = [MessageFixtures.message(1), MessageFixtures.message(2), bottom]
        fixture.list.children = latest
        latest[0].onPerform = { _ in fixture.list.children = earlier }
        bottom.onPerform = { _ in fixture.list.children = latest }

        let history = try History.read(fixture.view.destination, in: fixture.tree, since: "1700000001.000100",
            bounds: .init(maxItems: 20, maxPages: 10, deadline: Date().addingTimeInterval(5)), allowPartial: false)
        #expect(history.messages.map(\.ts) == (2...4).map { "170000000\($0).000100" })
        #expect(history.stopReason == .boundary)
        #expect(history.complete)
        #expect(history.pages == 2)
        #expect(history.scrollRestored)
        #expect(bottom.performCalls == [.scrollToVisible])
    }

    @Test func stalledHistoryRequiresOptInAndStillRestores() throws {
        let fixture = try ComposerFixture()
        let bottom = MessageFixtures.spacer()
        fixture.list.children = [MessageFixtures.message(1), bottom]
        let error = #expect(throws: RemoteError.self) {
            try History.read(fixture.view.destination, in: fixture.tree, since: nil,
                bounds: .init(maxItems: 20, maxPages: 20, deadline: Date().addingTimeInterval(10)), allowPartial: false)
        }
        #expect(error?.code == "partial_result")
        #expect(error?.exitStatus == 19)
        #expect(bottom.performCalls == [.scrollToVisible])
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
