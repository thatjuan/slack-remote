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

    @Test(arguments: ["people", "channels"])
    func explicitConversationScopeIsRejectedBeforeOpeningAWorkspaceSource(_ source: String) throws {
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.requireSupportedConversation(Fixture.result.conversation, for: source)
        }
        #expect(error?.code == "unsupported_destination")
        try SearchResults.requireSupportedConversation(nil, for: source)
    }

    @Test(arguments: ["messages", "files"])
    func explicitConversationScopeIsSupportedForMessagesAndFiles(_ source: String) throws {
        try SearchResults.requireSupportedConversation(Fixture.result.conversation, for: source)
    }

    @Test(arguments: ["people", "channels"])
    func workspaceSourcesLeaveAnActiveInFilterUntouched(_ source: String) throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
        fixture.filesTab.domID = source
        fixture.showConversationFilter()

        let error = #expect(throws: SearchResults.UnsupportedType.self) { try fixture.read(type: source) }
        #expect(error?.requiresUnscopedSearch == true)
        #expect(error?.available == ["messages", source])
        #expect(fixture.filesTab.performCalls.isEmpty)
    }

    @Test func workspacePeopleSearchReadsTheSelectedSource() throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
        let sources = fixture.showSources()
        let snapshot = try fixture.read(type: "people", timeout: 4)
        #expect(snapshot.results.map(\.content) == [.person(UserID("U0EEEEEEE"), label: "Ada")])
        #expect(sources.performCalls == [.press, .press])
    }

    @Test func workspacePeopleSearchReadsTheGridWithoutColumnDuplicates() throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
        fixture.showSources(peopleGrid: true)
        let snapshot = try fixture.read(type: "people", timeout: 4)
        #expect(snapshot.results.map(\.content) == [.person(nil, label: "Ada")])
        #expect(snapshot.complete)
    }

    @Test func scopedFilesKeepTheirFilterAndStructuredResults() throws {
        let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
        let sources = fixture.showSources(withBackdrop: false, ignoreFirstDismissal: true)
        fixture.showConversationFilter()
        let snapshot = try fixture.read(type: "files", timeout: 4, conversation: Fixture.result.conversation)
        #expect(snapshot.results.map(\.content) == [.file("F0DDDDDDD", name: "fixture.txt", conversation: nil)])
        #expect(sources.performCalls == [.press, .press, .press, .press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }

    @Test func waitsForScopedLauncherThenUsesFullSearchWithAnOldPaneStillVisible() throws {
        let scoped = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)], atEnd: false)
        scoped.showScopedResults(in: Fixture.result)
        let full = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
        full.showConversationFilter(title: "In: fixture")
        let transition = scoped.lateLauncher(to: full)
        let snapshot = try SearchResults.read(type: "files", team: Fixture.team, conversation: Fixture.result.conversation,
                                              in: transition.tree, bounds: .init(maxItems: 10, maxPages: 2,
                                                                                 deadline: Date().addingTimeInterval(2)),
                                              allowPartial: false)
        #expect(transition.launcher.performCalls == [.press])
        #expect(snapshot.results.map(\.content) == [.file("F0DDDDDDD", name: "fixture.txt", conversation: nil)])
    }

    @Test func changedOrMissingInFilterWithholdsFilesEvenAfterTheSourceIsReady() throws {
        for removesFilter in [false, true] {
            let fixture = try Fixture(rows: [Fixture.message(Fixture.firstTimestamp)])
            let filter = fixture.showConversationFilter(title: "In: fixture")
            let error = #expect(throws: SearchResults.UnsupportedType.self) {
                try SearchResults.read(type: "files", team: Fixture.team, conversation: Fixture.result.conversation,
                                       in: fixture.tree, bounds: .init(maxItems: 10, maxPages: 2,
                                                                       deadline: Date().addingTimeInterval(2)),
                                       allowPartial: true, onReady: {
                    if removesFilter { filter.domClasses = [] }
                    else { filter.attributes[.title] = .string("In: other") }
                })
            }
            #expect(error?.requiresUnscopedSearch == true)
        }
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
        try fixture.navigate(to: Fixture.start)
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: fixture.navigator(),
                                        keepOnSuccess: true, secondsSinceUserInput: { .infinity }) { submit in
                try submit(SlackWindow.currentWindow(in: fixture.tree))
                fixture.showFullResults()
                throw RemoteError.partialResult
            }
        }
        #expect(error?.code == "partial_result")
        #expect(fixture.links == [Fixture.start.channelLink])
        #expect(try SlackWindow.currentWindow(in: fixture.tree).location.destination == Fixture.start)
    }

    @Test func interruptionWhileReadingResultsClosesThePaneAndRestoresTheStartingConversation() throws {
        let row = Fixture.message(Fixture.firstTimestamp)
        let fixture = try Fixture(rows: [row], atEnd: false)
        try fixture.navigate(to: Fixture.start)
        row.onPerform = { action in
            #expect(action == .scrollToVisible)
            #expect(fixture.tree.requestInterruption())
        }

        #expect(throws: SlackTree.Interruption.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: fixture.navigator(),
                                        keepOnSuccess: true, secondsSinceUserInput: { .infinity }) { submit in
                try fixture.navigate(to: Fixture.result)
                try submit(SlackWindow.currentWindow(in: fixture.tree))
                fixture.showScopedResults(in: Fixture.result)
                return try fixture.read()
            }
        }
        #expect(row.performCalls == [.scrollToVisible])
        #expect(fixture.scopedClose?.performCalls == [.press])
        #expect(fixture.links == [Fixture.start.channelLink])
        #expect(try SlackWindow.currentWindow(in: fixture.tree).location.destination == Fixture.start)
    }

    @Test func emptyScopedFilesClosesOnlyTheDirectHeaderControlAndRestoresNotes() throws {
        let fixture = try Fixture(rows: [], atEnd: false)
        try fixture.navigate(to: Fixture.start)
        let back = try fixture.showEmptyScopedPane()
        let error = #expect(throws: SearchResults.UnsupportedType.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: fixture.navigator(),
                                        keepOnSuccess: false, secondsSinceUserInput: { .infinity }) { submit in
                try fixture.navigate(to: Fixture.result)
                try submit(SlackWindow.currentWindow(in: fixture.tree))
                fixture.showScopedResults(in: Fixture.result)
                return try fixture.read(type: "files", conversation: Fixture.result.conversation)
            }
        }
        #expect(error?.available == ["messages"])
        #expect(fixture.scopedClose?.performCalls == [.press])
        #expect(back.performCalls.isEmpty)
        #expect(fixture.links == [Fixture.start.channelLink])
        #expect(try SlackWindow.currentWindow(in: fixture.tree).location.destination == Fixture.start)
    }

    @Test func failedTransitionLeavesAnUnownedScopedPaneUntouched() throws {
        let fixture = try Fixture(rows: [], atEnd: false)
        try fixture.navigate(to: Fixture.start)
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: fixture.navigator(),
                                        keepOnSuccess: false, secondsSinceUserInput: { .infinity }) { _ in
                fixture.showScopedResults(in: Fixture.result)
                throw RemoteError.partialResult
            }
        }
        #expect(error?.code == "overlay_left_open")
        #expect(fixture.scopedClose?.performCalls.isEmpty == true)
        #expect(fixture.links.isEmpty)
    }

    @Test func fullSearchClosesTheRemountedOwnedPaneBeforeReturningToNotes() throws {
        let fixture = try Fixture(rows: [], atEnd: false)
        try fixture.navigate(to: Fixture.start)
        var links: [URL] = []
        let navigator = Navigator(openLink: { link in
            links.append(link)
            if link == Fixture.result.channelLink {
                try fixture.navigate(to: Fixture.result)
                fixture.showScopedResults(in: Fixture.result)
            } else {
                try fixture.navigate(to: Fixture.start)
            }
        }, frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
        let result = try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: navigator,
                                                 keepOnSuccess: false, scopedAnchor: Fixture.result,
                                                 secondsSinceUserInput: { .infinity }) { submit in
            try fixture.navigate(to: Fixture.result)
            try submit(SlackWindow.currentWindow(in: fixture.tree))
            fixture.showFullResults()
            return true
        }
        #expect(result)
        #expect(fixture.scopedClose?.performCalls == [.press])
        #expect(links == [Fixture.start.channelLink, Fixture.result.channelLink, Fixture.start.channelLink])
        #expect(try SlackWindow.currentWindow(in: fixture.tree).location.destination == Fixture.start)
    }

    @Test func withholdsResultsWhenRestorationCannotBeVerified() throws {
        let fixture = try Fixture(rows: [])
        try fixture.navigate(to: Fixture.start)
        let navigator = Navigator(openLink: { _ in throw RemoteError.internalError(operation: "fixture") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
        let error = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: Fixture.start, in: fixture.tree, navigator: navigator,
                                        keepOnSuccess: false, secondsSinceUserInput: { .infinity }) { submit in
                try submit(SlackWindow.currentWindow(in: fixture.tree))
                fixture.showFullResults()
                return try fixture.read()
            }
        }
        #expect(error?.code == "destination_mismatch")
    }
}
