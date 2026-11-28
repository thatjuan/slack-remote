@testable import SlackRemoteCore
import Testing

struct ListingTests {
    @Test func mapsConversationKindsAndResolvesOnlyOtherDMUsers() async throws {
        let fixtures = ReadCommandFixtures(
            """
            {"ok":true,"channels":[
              {"id":"C00000001","name":"public","is_channel":true,"is_private":false,"is_archived":true},
              {"id":"C00000002","name":"private","is_channel":true,"is_private":true,"is_archived":false},
              {"id":"D00000001","is_im":true,"user":"U00000002"},
              {"id":"G00000001","name":"mpdm-ada--viewer-1","is_mpim":true,"is_private":true},
              {"id":"D00000002","is_im":true,"user":"U00000001"},
              {"id":"D00000003","is_im":true,"user":""}
            ],"response_metadata":{"next_cursor":""}}
            """,
            #"{"ok":true,"user":{"id":"U00000002","name":"ada","profile":{"display_name":"Ada"}}}"#)
        let result = try await ChannelsRequest(includeArchived: true).run(in: fixtures.context())

        #expect(result.channels.map(\.kind) == [.channel, .privateChannel, .dm, .groupDM, .selfDM, .dm])
        #expect(result.channels.map(\.name) == ["public", "private", "Ada", "mpdm-ada--viewer-1", "Viewer", nil])
        #expect(result.channels.map { $0.user?.rawValue } == [nil, nil, "U00000002", nil, nil, nil])
        #expect(result.channels.map(\.archived) == [true, false, false, false, false, false])
        let requests = await fixtures.transport.requests
        #expect(requests.map(\.method) == ["users.conversations", "users.info"])
        #expect(requests.first?.params["types"] == "public_channel,private_channel,mpim,im")
        #expect(requests.first?.params["exclude_archived"] == "false")
    }

    @Test func publicDirectoryUsesConversationsList() async throws {
        let fixtures = ReadCommandFixtures(#"{"ok":true,"channels":[],"response_metadata":{"next_cursor":""}}"#)
        let result = try await ChannelsRequest(source: .all).run(in: fixtures.context())
        #expect(result.source == .all && result.complete)
        let calls = await fixtures.transport.requests
        #expect(calls.first?.method == "conversations.list")
        #expect(calls.first?.params["types"] == "public_channel")
        #expect(calls.first?.params["exclude_archived"] == "true")
    }

    @Test func peopleSkipsFilteredRowsAndSeedsEveryPage() async throws {
        let fixtures = ReadCommandFixtures(
            """
            {"ok":true,"members":[
              {"id":"USLACKBOT","name":"slackbot","is_bot":false,"deleted":false},
              {"id":"U00000004","name":"deleted","is_bot":false,"deleted":true}
            ],"response_metadata":{"next_cursor":"more-users"}}
            """,
            """
            {"ok":true,"members":[
              {"id":"U00000006","name":"build","is_bot":true,"deleted":false},
              {"id":"U00000002","name":"ada","deleted":false,"profile":{"real_name":"Ada Example","display_name":"Ada"}}
            ],"response_metadata":{"next_cursor":"last-page"}}
            """,
            """
            {"ok":true,"members":[{"id":"U00000003","name":"bea","deleted":false,"profile":{"real_name":"Bea"}}],
             "response_metadata":{"next_cursor":""}}
            """)
        let result = try await PeopleRequest(limit: 2).run(in: fixtures.context())

        #expect(result.people.map(\.name) == ["ada", "bea"])
        #expect(result.people.map(\.realName) == ["Ada Example", "Bea"])
        #expect(result.complete && result.pages == 3)
        let ids = ["USLACKBOT", "U00000004", "U00000006", "U00000002", "U00000003"].compactMap { UserID($0) }
        let names = try await fixtures.directory.names(for: Set(ids))
        #expect(ids.compactMap { names[$0] } == ["slackbot", "deleted", "build", "Ada", "Bea"])
        #expect(await fixtures.transport.requests.map { $0.params["limit"] } == ["2", "2", "1"])
    }

    @Test func listsDirectMessageMembers() async throws {
        let destination = Destination(team: ReadCommandFixtures.team, conversation: ConversationID("D00000001")!)
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"members":["U00000002"],"response_metadata":{"next_cursor":""}}"#,
            #"{"ok":true,"user":{"id":"U00000002","name":"ada","profile":{"display_name":"Ada"}}}"#)
        let result = try await MembersRequest(destination: destination).run(in: fixtures.context())
        #expect(result.members.map(\.name) == ["Ada"])
        #expect(result.members.map { $0.user.rawValue } == ["U00000002"])
        #expect(result.conversation == destination.conversation && result.complete)
        let calls = await fixtures.transport.requests
        #expect(calls.first?.method == "conversations.members")
        #expect(calls.first?.params["channel"] == "D00000001")
    }
}
