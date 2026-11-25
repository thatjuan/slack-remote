import Foundation
@testable import SlackRemoteCore
import Testing

struct SearchResultsTests {
    private typealias Fixture = SearchResultsFixture

    @Test func extractsMessageFromStructuralIdentity() {
        let row = Fixture.message(Fixture.firstTimestamp)
        #expect(SearchResults.content(type: "messages", row: row) == .message(
            .init(conversation: Fixture.result.conversation, ts: Fixture.firstTimestamp),
            sender: "Ada", text: "fixture excerpt"))
    }

    @Test func extractsFileAndItsConversation() {
        let row = Fixture.row(id: "F0DDDDDDD", name: "fixture.txt", conversation: "G0FFFFFFF")
        #expect(SearchResults.content(type: "files", row: row)
                == .file("F0DDDDDDD", name: "fixture.txt", conversation: Fixture.result.conversation))
    }

    @Test func extractsChannel() {
        let row = Fixture.row(id: "G0FFFFFFF", name: "fixture channel")
        #expect(SearchResults.content(type: "channels", row: row)
                == .channel(Fixture.result.conversation, name: "fixture channel"))
    }

    @Test func extractsPerson() {
        let row = Fixture.row(id: "U0EEEEEEE", name: "Ada")
        #expect(SearchResults.content(type: "people", row: row) == .person(UserID("U0EEEEEEE"), label: "Ada"))
    }

    @Test func doesNotTreatDisplayedTextAsAnID() throws {
        let row = Fixture.row(id: nil, sender: "Ada", text: "search-message-G0FFFFFFF-1700000000.000100")
        let fixture = try Fixture(rows: [row])
        let snapshot = try fixture.read()
        let output = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.results)) as? [[String: Any]])
        #expect(output.first?["idSource"] as? String == "none")
        #expect(output.first?["conversation"] is NSNull)
        #expect(output.first?["ts"] is NSNull)
    }

    @Test func pagesStopAtItemLimitAndEndOfList() throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp), Fixture.message(Fixture.secondTimestamp)])
        let limited = try fixture.read(maxItems: 1)
        #expect(limited.results.count == 1)
        #expect(limited.stopReason == .limit)
        #expect(!limited.complete)
        let complete = try fixture.read()
        #expect(complete.results.count == 2)
        #expect(complete.stopReason == .endOfList)
        #expect(complete.pages == 1)
        #expect(complete.complete)
    }

    @Test func stalledSearchRequiresOptIn() throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)], atEnd: false)
        let error = #expect(throws: RemoteError.self) { try fixture.read(timeout: 8) }
        #expect(error?.code == "partial_result")
        let partial = try fixture.read(timeout: 8, allowPartial: true)
        #expect(partial.stopReason == .stalled)
        #expect(partial.results.count == 1)
    }

    @Test func opensOnlyIndexedRowAndVerifiesTheRenderedMessage() throws {
        let first = Fixture.message(Fixture.firstTimestamp)
        let second = Fixture.message(Fixture.secondTimestamp)
        let fixture = try Fixture(rows: [first, second])
        second.onPerform = { _ in try fixture.navigate(to: Fixture.result, with: Fixture.secondTimestamp) }
        let snapshot = try fixture.read()
        let result = try SearchResults.open(1, from: snapshot, team: Fixture.team, in: fixture.tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.conversation == Fixture.result.conversation)
        #expect(result.ts == Fixture.secondTimestamp)
        #expect(!result.inThread)
        #expect(first.performCalls.isEmpty)
        #expect(second.performCalls == [.press])
    }

    @Test func aRenderedTimestampInAnotherConversationDoesNotVerifyArrival() throws {
        let row = Fixture.message(Fixture.firstTimestamp)
        let fixture = try Fixture(rows: [row])
        row.onPerform = { _ in try fixture.navigate(to: Fixture.start, with: Fixture.firstTimestamp) }
        let snapshot = try fixture.read()
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.open(0, from: snapshot, team: Fixture.team, in: fixture.tree,
                                   deadline: Date().addingTimeInterval(0.2))
        }
        #expect(error?.code == "destination_mismatch")
        #expect(row.performCalls == [.press])
    }

    @Test func refusesToPressAResultWithoutAnID() throws {
        let row = Fixture.message(Fixture.firstTimestamp, withID: false)
        let fixture = try Fixture(rows: [row])
        let snapshot = try fixture.read()
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.open(0, from: snapshot, team: Fixture.team, in: fixture.tree,
                                   deadline: Date().addingTimeInterval(1))
        }
        #expect(error?.code == "unsupported_destination")
        #expect(row.performCalls.isEmpty)
        #expect(try Fixture.timestamp(in: row).performCalls.isEmpty)
    }

    @Test func restoresTheStartingConversationAfterSearchFails() throws {
        let fixture = try Fixture(rows: [])
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: fixture.navigator(),
                                        keepOnSuccess: true) { throw RemoteError.partialResult }
        }
        #expect(error?.code == "partial_result")
        #expect(fixture.links == [Fixture.start.channelLink])
        #expect(try SlackWindow.currentWindow(in: fixture.tree).location.destination == Fixture.start)
    }

    @Test func withholdsResultsWhenRestorationCannotBeVerified() throws {
        let fixture = try Fixture(rows: [])
        let navigator = Navigator(openLink: { _ in throw RemoteError.internalError(operation: "fixture") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: navigator,
                                        keepOnSuccess: false) { try fixture.read() }
        }
        #expect(error?.code == "destination_mismatch")
    }
}
