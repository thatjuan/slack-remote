import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct ReactionsTests {
    private final class Fixture {
        let core: ComposerFixture
        let item = MessageFixtures.message(0)
        let popup: MessagePopupFixture
        let picker = FakeNode(role: "AXGroup", domClasses: Locators.emojiPicker.classes)
        let search = FakeNode(role: "AXTextField", domClasses: Locators.emojiSearch.classes)
        let add = FakeNode(role: "AXMenuItem", domClasses: Locators.addReaction.classes)
        let reactionBar = FakeNode(role: "AXGroup", domClasses: ["c-reaction_bar"])

        init() throws {
            core = try ComposerFixture()
            core.list.children.append(item)
            let body = try #require(try item.one(Locators.messageBody) as? FakeNode)
            body.children.append(reactionBar)
            popup = MessagePopupFixture(webArea: core.webArea, item: item)
            popup.menu.children = [add]
            picker.children = [search]
            search.settableAttributes = [.value]
            add.onPerform = { [weak self] _ in
                guard let self else { return }
                popup.replaceMenu(with: picker)
            }
        }

        func addReaction(named name: String?, own: Bool = true) {
            let button = MessageFixtures.reaction(title: "Synthetic reaction", description: "", reacted: own)
            if let name {
                button.children = [FakeNode(role: "AXImage", domClasses: Locators.emojiImage.classes,
                                            attributes: [.title: .string(":\(name):")])]
            }
            reactionBar.children.append(button)
        }

        func cell(_ name: String) -> FakeNode {
            FakeNode(role: "AXCell", domClasses: Locators.emojiCell.classes, domID: "emoji-picker-\(name)")
        }

        func run(_ emoji: String = "tada", timeout: TimeInterval = 3) throws -> Reactions.Receipt {
            try Reactions.add(emoji, to: ThreadFixture.root, in: core.view, tree: core.tree,
                              deadline: Date().addingTimeInterval(timeout), requireIdle: {})
        }
    }

    @Test func alreadyReactedDoesNotOpenAnything() throws {
        let fixture = try Fixture()
        fixture.addReaction(named: "tada")
        let receipt = try fixture.run()
        #expect(receipt.alreadyReacted)
        #expect(fixture.item.performCalls.isEmpty)
        #expect(fixture.add.performCalls.isEmpty)
    }

    @Test func refusesAnExistingUnnamedOwnReaction() throws {
        let fixture = try Fixture()
        fixture.addReaction(named: nil)
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "ui_drift")
        #expect(error?.message.contains("cannot tell which emoji") == true)
        #expect(fixture.item.performCalls.isEmpty)
    }

    @Test func anUnexpectedReactedControlStillBlocksThePicker() throws {
        let fixture = try Fixture()
        fixture.reactionBar.children = [FakeNode(role: "AXButton", domClasses: [Locators.reactionReacted])]
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "ui_drift")
        #expect(fixture.item.performCalls.isEmpty)
    }

    @Test func searchesAndPressesOnlyTheExactCell() throws {
        let fixture = try Fixture()
        let longer = fixture.cell("tada-bigger")
        let exact = fixture.cell("tada")
        fixture.picker.children.append(longer)
        fixture.search.onSet = { [weak fixture] attribute, value in
            if attribute == .value, value == .string("tada") { fixture?.picker.children.append(exact) }
        }
        exact.onPerform = { [weak fixture] _ in
            fixture?.addReaction(named: "tada")
            fixture?.popup.dismiss()
        }
        let receipt = try fixture.run()
        #expect(receipt.reacted)
        #expect(!receipt.alreadyReacted)
        #expect(fixture.search.setCalls.count == 1)
        #expect(exact.performCalls == [.press])
        #expect(longer.performCalls.isEmpty)
        #expect(try fixture.run().alreadyReacted)
        #expect(exact.performCalls == [.press])
    }

    @Test func unknownEmojiClosesThePickerWithoutPressingAnyCell() throws {
        let fixture = try Fixture()
        let longer = fixture.cell("tada-bigger")
        fixture.picker.children.append(longer)
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        guard case .unsafeText(let reason)? = error else {
            Issue.record("Expected unsafe_text")
            return
        }
        #expect(reason == "unknown emoji")
        #expect(longer.performCalls.isEmpty)
        #expect(fixture.popup.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.core.tree).isEmpty)
    }

    @Test func doesNotRetryAnUnconfirmedPress() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.picker.children.append(exact)
        exact.onPerform = { [weak fixture] _ in fixture?.popup.dismiss() }
        let error = #expect(throws: RemoteError.self) { try fixture.run(timeout: 0.3) }
        #expect(error?.code == "reaction_unconfirmed")
        #expect(exact.performCalls == [.press])
    }

    @Test func refusesToPressWhenThePickerHidesTheMessage() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.picker.children.append(exact)
        fixture.add.onPerform = { [weak fixture] _ in
            guard let fixture else { return }
            fixture.popup.replaceMenu(with: fixture.picker)
            fixture.core.list.children.removeAll { ($0 as? FakeNode) === fixture.item }
        }
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "message_not_rendered")
        #expect(exact.performCalls.isEmpty)
        #expect(fixture.popup.backdrop.performCalls == [.press])
    }
}
