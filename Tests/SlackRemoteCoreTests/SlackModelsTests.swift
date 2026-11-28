@testable import SlackRemoteCore
import Testing

struct SlackModelsTests {
    @Test func mapsBotFileAndReactionFields() async throws {
        let fixtures = ReadCommandFixtures(
            """
            {"ok":true,"messages":[
              {"text":"<https://example.org|done> :tada:","type":"message","subtype":"bot_message","bot_id":"B00000001",
               "ts":"1700000000.000100","bot_profile":{"id":"B00000001","name":"Build bot"},"username":"Bot",
               "edited":{"user":"U00000002","ts":"1700000001.000100"},
               "files":[{"id":"F00000001","name":"check.txt","title":"Check","mimetype":"text/plain","size":21,
                         "permalink":"https://example.slack.com/files/F00000001"}],
               "reactions":[{"name":"+1::skin-tone-2","count":3,"users":["U00000001","U00000002"]},
                            {"name":"tada","count":1,"users":["U00000002"]}]}
            ],"has_more":false}
            """)
        let result = try await ReadRequest(destination: ReadCommandFixtures.destination).run(in: fixtures.context())
        let message = try #require(result.messages.first)
        #expect(message.user == nil && message.userName == "Build bot")
        #expect(message.botId == "B00000001" && message.subtype == "bot_message")
        #expect(message.text == "<https://example.org|done> :tada:")
        #expect(message.edited)
        #expect(message.files.first?.size == 21)
        #expect(message.files.first?.mimetype == "text/plain")
        #expect(message.reactions.map(\.name) == ["+1::skin-tone-2", "tada"])
        #expect(message.reactions.map(\.count) == [3, 1])
        #expect(message.reactions.map(\.reacted) == [true, false])
        #expect(await fixtures.transport.requests.count == 1)
    }
}
