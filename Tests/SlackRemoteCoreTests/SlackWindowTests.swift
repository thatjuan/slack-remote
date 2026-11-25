import SlackRemoteCore
import Testing

struct SlackWindowTests {
    private let target = Destination(team: TeamID("T0AAAAAAA")!, conversation: ConversationID("C0BBBBBBB")!)

    @Test func verifiesMatchingWindow() throws {
        let window = SlackFixture.window()
        let view = try SlackWindow.verify(target, in: SlackTree(windows: [window]))
        #expect(view.destination == target)
        #expect(view.window as? FakeNode === window)
        #expect(Locators.primaryView.matches(view.primaryView))
    }

    @Test func rejectsDifferentConversation() {
        let tree = SlackTree(windows: [SlackFixture.window(conversation: "D0CCCCCCC")])
        let error = #expect(throws: RemoteError.self) { try SlackWindow.verify(target, in: tree) }
        #expect(error?.code == "destination_mismatch")
    }

    @Test func rejectsSidebarSelectionThatDisagreesWithURL() throws {
        let window = SlackFixture.window(conversation: "D0CCCCCCC")
        let web = try #require(try window.one(Locators.webArea) as? FakeNode)
        web.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/C0BBBBBBB")
        let tree = SlackTree(windows: [window])
        let error = #expect(throws: RemoteError.self) { try SlackWindow.verify(target, in: tree) }
        #expect(error?.code == "destination_mismatch")
    }

    @Test func acceptsNoRenderedSelection() throws {
        let tree = SlackTree(windows: [SlackFixture.window(sidebar: ["D0CCCCCCC"])])
        let view = try SlackWindow.verify(target, in: tree)
        #expect(view.destination == target)
    }

    @Test func rejectsTwoMatchingWindows() {
        let tree = SlackTree(windows: [SlackFixture.window(), SlackFixture.window(isMain: false)])
        let error = #expect(throws: RemoteError.self) { try SlackWindow.verify(target, in: tree) }
        #expect(error?.code == "ambiguous_window")
    }

    @Test func picksTheMainWindow() throws {
        let main = SlackFixture.window(conversation: "D0CCCCCCC")
        let tree = SlackTree(windows: [SlackFixture.window(isMain: false), main])
        let current = try SlackWindow.currentWindow(in: tree)
        #expect(current.window as? FakeNode === main)
    }
}
