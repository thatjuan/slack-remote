import SlackRemoteCore
import Testing

struct SearchModalTests {
    @Test func appliesOnlyTheRequestedConversationFilter() throws {
        let fixture = try SearchModalFixture()
        try fixture.run()
        #expect(fixture.inFilter.performCalls == [.press])
        #expect(fixture.unrelated.performCalls.isEmpty)
        #expect(fixture.submit.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }

    @Test func refusesAnotherConversationsFilterAndClosesTheModal() throws {
        let fixture = try SearchModalFixture(includeMatchingFilter: false)
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "ui_drift")
        #expect(fixture.unrelated.performCalls.isEmpty)
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }

    @Test func clearsAMismatchedQueryAndRollsBackTheFilterBeforeClosing() throws {
        let fixture = try SearchModalFixture(queryReadback: "changed by client")
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "ui_drift")
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.inFilter.performCalls == [.press, .press])
        #expect(fixture.clear.performCalls == [.press])
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }
}
