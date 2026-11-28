import os
@testable import SlackRemoteCore
import Testing

struct SearchTests {
    @Test(arguments: 0..<8) func appendsWorkspaceModifiersInOrder(flags: Int) async throws {
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"messages":{"total":0,"paging":{"page":1,"pages":0},"matches":[]}}"#)
        let fromMe = flags & 1 != 0
        let hasLink = flags & 2 != 0
        let threadsOnly = flags & 4 != 0
        let result = try await SearchRequest(query: "deploy", fromMe: fromMe, hasLink: hasLink,
                                             threadsOnly: threadsOnly, sort: .timestamp)
            .run(in: fixtures.context())
        let query = ["deploy", fromMe ? "from:<@U00000001>" : nil, hasLink ? "has:link" : nil,
                     threadsOnly ? "is:thread" : nil].compactMap { $0 }.joined(separator: " ")
        #expect(result.query == query)
        #expect(await fixtures.transport.requests.first?.params == [
            "query": query, "count": "50", "page": "1", "sort": "timestamp", "sort_dir": "desc", "highlight": "false",
        ])
    }

    @Test func filtersMismatchedChannelsAndAuthorsAcrossSearchPages() async throws {
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"channel":{"id":"C00000001","name":"eng","is_channel":true,"is_private":true}}"#,
            """
            {"ok":true,"messages":{"total":4,"paging":{"count":3,"page":1,"pages":2,"total":4},"matches":[
              {"ts":"1700000000.000100","channel":{"id":"C00000002","name":"elsewhere"},"user":"U00000001",
               "text":"deploy","permalink":"https://example.slack.com/archives/C00000002/p1700000000000100"},
              {"ts":"1700000000.000200","channel":{"id":"C00000001","name":"eng"},"user":"U00000002",
               "text":"deploy","permalink":"https://example.slack.com/archives/C00000001/p1700000000000200"},
              {"ts":"1700000000.000250","channel":{"id":"C00000001","name":"eng"},"user":"U00000001",
               "text":"deploy","permalink":"https://example.slack.com/archives/C00000001/p1700000000000250"}
            ]}}
            """,
            """
            {"ok":true,"messages":{"total":4,"paging":{"count":3,"page":2,"pages":2,"total":4},"matches":[
              {"ts":"1700000000.000300","channel":{"id":"C00000001","name":"eng"},"user":"U00000001",
               "text":"deploy","permalink":"https://example.slack.com/archives/C00000001/p1700000000000300"}
            ]}}
            """,
            #"{"ok":true,"user":{"id":"U00000001","name":"viewer","profile":{"display_name":"Viewer"}}}"#)
        let warnings = OSAllocatedUnfairLock(initialState: [String]())
        let result = try await SearchRequest(query: "deploy", channel: ReadCommandFixtures.channel, fromMe: true,
                                             hasLink: true, threadsOnly: true, limit: 3)
            .run(in: fixtures.context { warning in warnings.withLock { $0.append(warning) } })

        #expect(result.query == "deploy in:#eng from:<@U00000001> has:link is:thread")
        #expect(result.total == 4 && result.complete && result.stopReason == .endOfList && result.pages == 2)
        #expect(warnings.withLock { $0 } == ["filtered_2"])
        guard case .message(let message) = try #require(result.results.first) else {
            Issue.record("Expected a search message.")
            return
        }
        #expect(result.results.count == 2 && message.ts == "1700000000.000250" && message.userName == "Viewer")
        let calls = await fixtures.transport.requests
        #expect(calls.map(\.method) == ["conversations.info", "search.messages", "search.messages", "users.info"])
        #expect(calls.compactMap { $0.params["page"] } == ["1", "2"])
        #expect(calls.compactMap { $0.params["count"] } == ["3", "3"])
    }

    @Test func directMessageSearchUsesTheHandleAndFileShares() async throws {
        let dm = ConversationID("D00000001")!
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"channel":{"id":"D00000001","is_im":true,"user":"U00000002"}}"#,
            #"{"ok":true,"user":{"id":"U00000002","name":"ada","profile":{"display_name":"Ada"}}}"#,
            """
            {"ok":true,"files":{"total":1,"paging":{"count":50,"page":1,"pages":1,"total":1},"matches":[
              {"id":"F00000001","name":"file.txt","title":"File","mimetype":"text/plain","size":5,
               "created":1700000000,"ims":["D00000001"],"permalink":"https://example.slack.com/files/F00000001"}
            ]}}
            """)
        let result = try await SearchRequest(query: "file", type: .files, channel: dm).run(in: fixtures.context())
        #expect(result.query == "file in:@ada")
        guard case .file(let file) = try #require(result.results.first) else {
            Issue.record("Expected a search file.")
            return
        }
        #expect(file.id == "F00000001" && file.created == 1700000000)
        #expect(await fixtures.transport.requests.map(\.method) == ["conversations.info", "users.info", "search.files"])
    }

    @Test func rejectsGroupDMSearch() async {
        let group = ConversationID("G00000001")!
        let fixtures = ReadCommandFixtures(#"{"ok":true,"channel":{"id":"G00000001","is_mpim":true,"is_private":true}}"#)
        await #expect(throws: RemoteError.unsupportedDestination) {
            try await SearchRequest(query: "deploy", channel: group).run(in: fixtures.context())
        }
        #expect(await fixtures.transport.requests.count == 1)
    }
}
