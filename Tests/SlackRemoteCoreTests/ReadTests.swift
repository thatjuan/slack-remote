@testable import SlackRemoteCore
import Testing

struct ReadTests {
    @Test func reversesHistoryAcrossCursorPagesAndSendsBounds() async throws {
        let fixtures = ReadCommandFixtures(
            """
            {"ok": true, "messages": [
              {"type":"message","ts":"1700000000.000300","text":"newest"},
              {"type":"message","ts":"1700000000.000200","text":"second"}
            ], "has_more":true,"response_metadata":{"next_cursor":"older"}}
            """,
            """
            {"ok": true, "messages":[{"type":"message","ts":"1700000000.000100","text":"older"}],
             "has_more":true,"response_metadata":{"next_cursor":"unused"}}
            """)
        let result = try await ReadRequest(destination: ReadCommandFixtures.destination,
                                           since: "1699999999.999999", until: "1700000000.000400", limit: 3)
            .run(in: fixtures.context())

        #expect(result.messages.map(\.text) == ["older", "second", "newest"])
        #expect(result.oldestTs == "1700000000.000100")
        #expect(result.newestTs == "1700000000.000300")
        #expect(result.stopReason == .limit)
        #expect(!result.complete)
        #expect(result.pages == 2)
        let calls = await fixtures.transport.requests
        #expect(calls.map(\.method) == ["conversations.history", "conversations.history"])
        #expect(calls.map(\.params) == [
            ["channel":"C00000001", "limit":"3", "oldest":"1699999999.999999", "latest":"1700000000.000400"],
            ["channel":"C00000001", "limit":"1", "oldest":"1699999999.999999", "latest":"1700000000.000400",
             "cursor":"older"],
        ])
    }

    @Test(arguments: [true, false]) func distinguishesBoundaryFromEndOfList(hasSince: Bool) async throws {
        let fixtures = ReadCommandFixtures(#"{"ok":true,"messages":[],"has_more":false}"#)
        let result = try await ReadRequest(destination: ReadCommandFixtures.destination,
                                           since: hasSince ? "1700000000.000100" : nil)
            .run(in: fixtures.context())
        #expect(result.stopReason == (hasSince ? .boundary : .endOfList))
        #expect(result.complete)
        #expect(result.oldestTs == nil && result.newestTs == nil)
    }

    @Test(arguments: ["1700000000.000100", "1700000000.000200"]) func rejectsAReplyAsTheThread(ts: String) async {
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"messages":[{"ts":"1700000000.000200","thread_ts":"1700000000.000100","text":"reply"}]}"#)
        await #expect(throws: RemoteError.messageNotFound) {
            try await ReadRequest(destination: ReadCommandFixtures.destination, thread: ts).run(in: fixtures.context())
        }
    }

    @Test func retainsParentAndRepliesInSlackOrder() async throws {
        let fixtures = ReadCommandFixtures(
            """
            {"ok":true,"messages":[
              {"ts":"1700000000.000100","thread_ts":"1700000000.000100","reply_count":1,"text":"parent"},
              {"ts":"1700000000.000200","thread_ts":"1700000000.000100","text":"reply"}
            ],"has_more":false}
            """)
        let result = try await ReadRequest(destination: ReadCommandFixtures.destination, thread: "1700000000.000100")
            .run(in: fixtures.context())
        #expect(result.messages.map(\.text) == ["parent", "reply"])
        #expect(result.messages.map(\.threadTs) == ["1700000000.000100", "1700000000.000100"])
        #expect(result.messages.map(\.replyCount) == [1, nil])
    }

    @Test func deadlineIncludesThePartialResult() async throws {
        let fixtures = ReadCommandFixtures(seconds: -1)
        let destination = ReadCommandFixtures.destination
        let result = try await ReadRequest(destination: destination, allowPartial: true).run(in: fixtures.context())
        #expect(result.stopReason == .deadline && !result.complete && result.pages == 0)
        do {
            _ = try await ReadRequest(destination: destination).run(in: fixtures.context())
            Issue.record("Expected partial_result.")
        } catch let error as OperationFailure<ReadResult> {
            #expect(error.error == .partialResult)
            #expect(error.result.stopReason == .deadline && error.result.messages.isEmpty)
        }
    }
}
