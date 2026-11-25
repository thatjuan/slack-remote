import SlackRemoteCore
import Testing

struct DestinationTests {
    private static let team = TeamID("T0AAAAAAA")!
    private static let channel = Destination(team: team, conversation: ConversationID("C0BBBBBBB")!)
    private static let dm = Destination(team: team, conversation: ConversationID("D0CCCCCCC")!)

    @Test(arguments: [
        ("https://app.slack.com/client/T0AAAAAAA/C0BBBBBBB", ClientLocation.conversation(channel, trailing: [])),
        ("https://app.slack.com/client/T0AAAAAAA/D0CCCCCCC/thread/D0CCCCCCC-1700000000.000100",
         .conversation(dm, trailing: ["thread", "D0CCCCCCC-1700000000.000100"])),
        ("https://app.slack.com/client/T0AAAAAAA/threads", .other(team: team, path: ["threads"])),
        ("https://app.slack.com/client/T0AAAAAAA", .other(team: team, path: [])),
        ("https://app.slack.com/signin", .notClient),
        ("https://example.com/client/T0AAAAAAA/C0BBBBBBB", .notClient),
    ])
    func parsesClientURL(url: String, location: ClientLocation) {
        #expect(ClientLocation.parse(url: url) == location)
    }

    @Test func validatesIDs() {
        #expect(TeamID("E0AAAAAAA") != nil)
        #expect(TeamID("C0BBBBBBB") == nil)
        #expect(ConversationID("G0BBBBBBB")?.kind == .group)
        #expect(ConversationID("C0BBBBBB") == nil)
        #expect(UserID("W0AAAAAAA") != nil)
        #expect(UserID("U0aaaaaaa") == nil)
    }

    @Test func buildsDeepLinks() {
        #expect(Self.channel.channelLink.absoluteString == "slack://channel?team=T0AAAAAAA&id=C0BBBBBBB")
        #expect(Self.dm.userLink(UserID("U0DDDDDDD")!).absoluteString == "slack://user?team=T0AAAAAAA&id=U0DDDDDDD")
    }
}
