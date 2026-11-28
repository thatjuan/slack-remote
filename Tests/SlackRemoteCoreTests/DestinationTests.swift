import SlackRemoteCore
import Testing

struct DestinationTests {
    @Test func validatesIDs() {
        #expect(TeamID("E0AAAAAAA") != nil)
        #expect(TeamID("C0BBBBBBB") == nil)
        #expect(ConversationID("G0BBBBBBB")?.kind == .group)
        #expect(ConversationID("C0BBBBBB") == nil)
        #expect(UserID("W0AAAAAAA") != nil)
        #expect(UserID("U0aaaaaaa") == nil)
    }
}
