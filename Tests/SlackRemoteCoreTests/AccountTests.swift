import Foundation
import SlackRemoteCore
import Testing

@MainActor
struct AccountTests {
    private let team = TeamID("T0AAAAAAA")!
    private let user = UserID("U0EEEEEEE")!
    private let selfDM = ConversationID("D0CCCCCCC")!

    private func configuration(selfDM: ConversationID?) -> Config {
        var config = Config()
        config.saveAccount(Account(team: team, user: user, selfDM: selfDM))
        return config
    }

    @Test func noConfigWarnsOnlyForWrites() throws {
        let tree = SlackTree(windows: [SlackFixture.window()])
        var warnings: [String] = []
        for access in [Account.Access.read, .write] {
            let check = try Account.verify(team: team, in: tree, config: nil, access: access, deadline: .distantFuture) {
                warnings.append($0)
            }
            #expect(check == .unconfigured)
        }
        #expect(warnings == ["no_account_configured"])
    }

    @Test func missingAccountWarnsForReadsAndRejectsWrites() throws {
        let tree = SlackTree(windows: [SlackFixture.window()])
        var warnings: [String] = []
        let read = try Account.verify(team: team, in: tree, config: Config(), access: .read, deadline: .distantFuture) {
            warnings.append($0)
        }
        #expect(read == .unverified)
        #expect(warnings == ["account_unverified"])
        for access in [Account.Access.write, .dryRunWrite] {
            let error = #expect(throws: RemoteError.self) {
                try Account.verify(team: team, in: tree, config: Config(), access: access, deadline: .distantFuture)
            }
            #expect(error?.code == "account_unverified")
        }
    }

    @Test func renderedSidebarIdentityMustMatchSavedDM() throws {
        let fixture = try ComposerFixture()
        let control = try #require(fixture.window.all(Locators.sidebarRowTarget).last as? FakeNode)
        control.domClasses.append(Locators.selfDM)
        let matched = try Account.verify(team: team, in: fixture.tree, config: configuration(selfDM: selfDM),
                                        access: .write, deadline: .distantFuture)
        #expect(matched == .verified)
        let error = #expect(throws: RemoteError.self) {
            try Account.verify(team: team, in: fixture.tree, config: configuration(selfDM: ConversationID("D0FFFFFFF")),
                               access: .read, deadline: .distantFuture)
        }
        #expect(error?.code == "account_mismatch")
    }

    @Test func identifiesTheSelfDMConversationAlongsideAShortcut() throws {
        let window = SlackFixture.window(sidebar: ["C0BBBBBBB", selfDM.rawValue, "self-dm-shortcut"])
        let rows = window.all(Locators.sidebarRowTarget).compactMap { $0 as? FakeNode }
        for row in rows.suffix(2) { row.domClasses.append(Locators.selfDM) }
        #expect(try Account.sidebarSelfDM(in: window) == selfDM)
    }

    @Test func whenSidebarRowIsMissingOnlyWritesCheckSearchModal() throws {
        let fixture = try ComposerFixture()
        let button = FakeNode(role: "AXButton", domClasses: Locators.searchButton.classes)
        fixture.webArea.children.append(button)
        let unblocked = fixture.webArea.children
        let filter = FakeNode(role: "AXCheckBox", domID: Locators.selfFilterPrefix + user.rawValue)
        let clear = FakeNode(role: "AXButton", domClasses: Locators.searchClear.classes)
        let modal = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent], children: [filter, clear])
        let overlay = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
        button.onPerform = { _ in fixture.webArea.children = [modal, overlay] }
        overlay.onPerform = { _ in fixture.webArea.children = unblocked }

        let config = configuration(selfDM: selfDM)
        for access in [Account.Access.read, .dryRunWrite] {
            var warnings: [String] = []
            let read = try Account.verify(team: team, in: fixture.tree, config: config, access: access,
                                          deadline: .distantFuture) { warnings.append($0) }
            #expect(read == .unverified)
            #expect(warnings == ["account_unverified"])
        }
        #expect(button.performCalls.isEmpty)
        let write = try Account.verify(team: team, in: fixture.tree, config: config,
                                      access: .write, deadline: Date().addingTimeInterval(1))
        #expect(write == .verified)
        #expect(button.performCalls == [.press])
        #expect(clear.performCalls == [.press])
        #expect(overlay.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)

        filter.domID = Locators.selfFilterPrefix + "U0FFFFFFF"
        let error = #expect(throws: RemoteError.self) {
            try Account.verify(team: team, in: fixture.tree, config: config,
                               access: .write, deadline: Date().addingTimeInterval(1))
        }
        #expect(error?.code == "account_mismatch")
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }
}
