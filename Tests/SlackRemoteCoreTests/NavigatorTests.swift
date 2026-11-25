import Foundation
@testable import SlackRemoteCore
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

    @Test(arguments: ["D0CCCCCCC", "G0FFFFFFF"])
    func allConversationKindsUseTheChannelLinkByDefault(_ id: String) throws {
        let destination = Destination(team: team, conversation: ConversationID(id)!)
        var window = SlackFixture.window()
        let tree = SlackTree(refresh: { [window] })
        var links: [URL] = []
        let navigator = navigator { url in
            links.append(url)
            window = SlackFixture.window(conversation: id)
        }
        let result = try navigator.navigate(to: destination, user: nil, interrupt: false, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .deepLinkChannel)
        #expect(links == [destination.channelLink])
    }

    @Test func forcedSidebarPressesTheInnerConversationControl() throws {
        var window = SlackFixture.window()
        let tree = SlackTree(refresh: { [window] })
        let row = try #require(window.all(Locators.sidebarRow).first { $0.domID == dm.conversation.rawValue } as? FakeNode)
        let control = try #require(row.children.first as? FakeNode)
        control.onPerform = { _ in window = SlackFixture.window(conversation: self.dm.conversation.rawValue) }
        let navigator = navigator { _ in Issue.record("Sidebar navigation opened a link") }
        let result = try navigator.navigate(to: dm, user: nil, interrupt: false, preference: .sidebar, in: tree,
                                            deadline: Date().addingTimeInterval(2))
        #expect(result.route == .sidebarRow)
        #expect(row.performCalls.isEmpty)
        #expect(control.performCalls == [.press])
    }

    @Test func missingRowIsUnreachable() {
        let tree = SlackTree(windows: [SlackFixture.window(sidebar: [channel.conversation.rawValue])])
        let navigator = navigator { _ in Issue.record("Missing row triggered a link") }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: dm, user: nil, interrupt: false, preference: .sidebar,
                                   in: tree, deadline: Date().addingTimeInterval(2))
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
            try navigator.navigate(to: dm, user: nil, interrupt: false, preference: .sidebar,
                                   in: SlackTree(windows: [window]),
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

    @Test func reportsAnOverlayThatAppearedDuringNavigation() throws {
        var window = SlackFixture.window(conversation: dm.conversation.rawValue)
        let tree = SlackTree(refresh: { [window] })
        let popup = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])
        let navigator = navigator { _ in
            window = SlackFixture.window()
            window.children.append(popup)
        }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: channel, user: nil, interrupt: false, forReading: true, in: tree,
                                   deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "overlay_left_open")
        #expect(popup.performCalls.isEmpty)
    }

    @Test func opensAndLeavesReadableSelfDMWithoutTouchingItsPopoverOrDraft() throws {
        let fixture = try selfDMWithAttachmentPopover()
        let notes = SlackFixture.window()
        var window = notes
        let tree = SlackTree(refresh: { [window] })
        var links: [URL] = []
        let navigator = navigator { url in
            links.append(url)
            window = url == self.dm.channelLink ? fixture.window : notes
        }
        let deadline = Date().addingTimeInterval(3)
        let entered = try navigator.navigate(to: dm, user: nil, interrupt: false, forReading: true,
                                             in: tree, deadline: deadline)
        #expect(entered.route == .deepLinkChannel)
        let view = try SlackWindow.verifyForReading(dm, in: tree)
        _ = try MessageReader.read(view, limit: nil)
        let error = #expect(throws: RemoteError.self) { try SlackWindow.verify(dm, in: tree) }
        #expect(error?.code == "ui_blocked")
        let exited = try navigator.navigate(to: channel, user: nil, interrupt: false, forReading: true,
                                            in: tree, deadline: deadline)
        #expect(exited.route == .deepLinkChannel)
        #expect(links == [dm.channelLink, channel.channelLink])
        #expect(fixture.backdrop.performCalls.isEmpty)
        #expect(fixture.popup.performCalls.isEmpty)
        #expect(fixture.popup.descendants().compactMap { $0 as? FakeNode }.allSatisfy { $0.performCalls.isEmpty })
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(fixture.editor.string(.value) == "Existing draft")
    }

    enum UnverifiedState: CaseIterable { case selection, selfMarker, list, focus, backdrop, modal }

    @Test(arguments: UnverifiedState.allCases)
    func unverifiedPopoverOrConversationBlocksReadNavigation(_ failure: UnverifiedState) throws {
        let fixture = try selfDMWithAttachmentPopover()
        switch failure {
        case .selection: fixture.row.domClasses.removeAll { $0 == Locators.sidebarRowSelected }
        case .selfMarker: fixture.row.domClasses.removeAll { $0 == Locators.selfDM }
        case .list:
            let list = try #require(try fixture.window.one(Locators.messageList) as? FakeNode)
            list.children = []
        case .focus: fixture.popup.attributes[.focused] = .bool(true)
        case .backdrop: fixture.backdrop.domClasses.removeAll { $0 == "c-popover--no-pointer" }
        case .modal:
            fixture.window.children.append(FakeNode(role: "AXGroup", subrole: "AXApplicationDialog",
                                                    domClasses: [Locators.modalContent]))
        }
        let navigator = navigator { _ in Issue.record("Navigation started under an unverified popover") }
        let error = #expect(throws: RemoteError.self) {
            try navigator.navigate(to: channel, user: nil, interrupt: false, forReading: true,
                                   in: SlackTree(windows: [fixture.window]), deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "ui_blocked")
        #expect(fixture.backdrop.performCalls.isEmpty)
        #expect(fixture.editor.setCalls.isEmpty)
    }

    private func selfDMWithAttachmentPopover() throws
        -> (window: FakeNode, editor: FakeNode, row: FakeNode, backdrop: FakeNode, popup: FakeNode) {
        let window = SlackFixture.window(conversation: dm.conversation.rawValue)
        let row = try #require(window.all(Locators.sidebarRow).first { $0.domID == dm.conversation.rawValue } as? FakeNode)
        row.domClasses.append(Locators.selfDM)
        let target = try #require(try row.one(Locators.sidebarRowTarget) as? FakeNode)
        target.attributes[.enabled] = .bool(true)
        target.actionNames = [UIAction.press.rawValue]
        let editor = try #require(try window.one(Locators.composerEditor) as? FakeNode)
        editor.domClasses.removeAll { $0 == Locators.composerBlank }
        editor.attributes[.value] = .string("Existing draft")
        editor.attributes[.enabled] = .bool(true)
        let text = FakeNode(role: "AXStaticText")
        let link = FakeNode(role: "AXLink", domClasses: Locators.attachmentPopoverLink.classes, children: [text])
        let popup = FakeNode(role: "AXGroup", domClasses: Locators.attachmentPopover.classes,
                             children: [link, FakeNode(role: "AXStaticText"), FakeNode(role: "AXStaticText")],
                             attributes: [.focused: .bool(false)])
        let backdrop = FakeNode(role: "AXGroup", domClasses: Locators.attachmentPopoverBackdrop.classes, children: [popup])
        let portal = FakeNode(role: "AXGroup", domClasses: Locators.modalPortal.classes, children: [backdrop])
        let webArea = try #require(try window.one(Locators.webArea) as? FakeNode)
        webArea.children.append(portal)
        return (window, editor, row, backdrop, popup)
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
