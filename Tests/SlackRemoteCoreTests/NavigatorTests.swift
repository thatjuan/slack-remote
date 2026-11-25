import Foundation
import SlackRemoteCore
import Testing

@MainActor
struct NavigatorTests {
    private let team = TeamID("T0AAAAAAA")!
    private let user = UserID("U0DDDDDDD")!
    private var channel: Destination { Destination(team: team, conversation: ConversationID("C0BBBBBBB")!) }
    private var dm: Destination { Destination(team: team, conversation: ConversationID("D0CCCCCCC")!) }

    private func navigator(frontmost: String? = nil, idle: Double = 60,
                           openLink: @escaping (URL) throws -> Void) -> Navigator {
        Navigator(openLink: openLink, frontmostBundleID: { frontmost }, activate: { _ in },
                  secondsSinceUserInput: { idle })
    }

    @Test func channelUsesTheChannelLink() throws {
        var window = SlackFixture.window(conversation: dm.conversation.rawValue)
        let tree = SlackTree(refresh: { [window] })
        var links: [URL] = []
        let navigator = navigator { url in
            links.append(url)
            window = SlackFixture.window()
        }
        let result = try navigator.navigate(to: channel, user: nil, interrupt: false, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .deepLinkChannel)
        #expect(links == [channel.channelLink])
    }

    @Test func dmWithUserUsesTheUserLink() throws {
        var window = SlackFixture.window()
        let tree = SlackTree(refresh: { [window] })
        var links: [URL] = []
        let navigator = navigator { url in
            links.append(url)
            window = SlackFixture.window(conversation: self.dm.conversation.rawValue)
        }
        let result = try navigator.navigate(to: dm, user: user, interrupt: false, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .deepLinkUser)
        #expect(links == [dm.userLink(user)])
    }

    @Test func dmWithoutUserPressesTheSidebarConversationControl() throws {
        var window = SlackFixture.window()
        let tree = SlackTree(refresh: { [window] })
        let row = try #require(window.all(Locators.sidebarRow).first { $0.domID == dm.conversation.rawValue } as? FakeNode)
        let control = try #require(row.children.first as? FakeNode)
        control.onPerform = { _ in window = SlackFixture.window(conversation: self.dm.conversation.rawValue) }
        let navigator = navigator { _ in Issue.record("Sidebar navigation opened a link") }
        let result = try navigator.navigate(to: dm, user: nil, interrupt: false, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .sidebarRow)
        #expect(row.performCalls.isEmpty)
        #expect(control.performCalls == [.press])
    }

    @Test func missingRowIsUnreachable() {
        let tree = SlackTree(windows: [SlackFixture.window(sidebar: [channel.conversation.rawValue])])
        let navigator = navigator { _ in Issue.record("Missing row triggered a link") }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: dm, user: nil, interrupt: false, in: tree, deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "destination_unreachable")
    }

    @Test func ambiguousSidebarControlsAreNeverPressed() throws {
        let window = SlackFixture.window()
        let row = try #require(window.all(Locators.sidebarRow).first { $0.domID == dm.conversation.rawValue } as? FakeNode)
        let control = try #require(row.children.first as? FakeNode)
        let extra = FakeNode(role: control.role, subrole: control.subrole, domClasses: control.domClasses)
        row.children.append(extra)
        let navigator = navigator { _ in Issue.record("Ambiguous sidebar controls triggered a link") }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: dm, user: nil, interrupt: false, in: SlackTree(windows: [window]),
                                   deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "ui_drift")
        #expect(row.performCalls.isEmpty)
        #expect(control.performCalls.isEmpty)
        #expect(extra.performCalls.isEmpty)
    }

    @Test func alreadyThereOpensNothingEvenWithRecentInput() throws {
        let tree = SlackTree(windows: [SlackFixture.window()])
        let navigator = navigator(frontmost: SlackApp.bundleIdentifier, idle: 0) { _ in
            Issue.record("Already-there navigation opened a link")
        }
        let result = try navigator.navigate(to: channel, user: nil, interrupt: false, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .alreadyThere)
        #expect(!result.focusRestored)
    }

    @Test func unchangedTreeFailsWithDestinationMismatch() {
        let tree = SlackTree(windows: [SlackFixture.window(conversation: dm.conversation.rawValue)])
        var links: [URL] = []
        let navigator = navigator { links.append($0) }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: channel, user: nil, interrupt: false, in: tree,
                                   deadline: Date().addingTimeInterval(0.25))
        }
        #expect(error?.code == "destination_mismatch")
        #expect(links == [channel.channelLink])
    }

    @Test func recentInputWhileSlackIsFrontmostBlocksNavigation() {
        let tree = SlackTree(windows: [SlackFixture.window(conversation: dm.conversation.rawValue)])
        let navigator = navigator(frontmost: SlackApp.bundleIdentifier, idle: 0) { _ in
            Issue.record("Navigation occurred during recent user input")
        }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: channel, user: nil, interrupt: false, in: tree,
                                   deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "slack_in_use")
    }
}
