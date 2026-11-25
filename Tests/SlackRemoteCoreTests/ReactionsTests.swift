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
        let row = FakeNode(role: "AXRow", domClasses: Locators.emojiResultsRow.classes)
        let column = FakeNode(role: "AXColumn")
        let add = FakeNode(role: "AXMenuItem", domClasses: Locators.addReaction.classes,
                           attributes: [.enabled: .bool(true)])
        let reactionBar = FakeNode(role: "AXGroup", domClasses: ["c-reaction_bar"])
        let visibleRoots: [any UINode]

        init() throws {
            core = try ComposerFixture()
            visibleRoots = core.webArea.children
            core.list.children.append(item)
            let selfRow = try #require(core.window.all(Locators.sidebarRow).last as? FakeNode)
            selfRow.domClasses.append(Locators.selfDM)
            let body = try #require(try item.one(Locators.messageBody) as? FakeNode)
            body.children.append(reactionBar)
            popup = MessagePopupFixture(webArea: core.webArea, item: item)
            popup.menu.children = [add]
            let table = FakeNode(role: "AXTable", domClasses: Locators.emojiResultsTable.classes, children: [row, column])
            picker.children = [search, FakeNode(role: "AXGroup", domClasses: Locators.emojiResults.classes, children: [table])]
            search.settableAttributes = [.value]
            add.actionNames = [UIAction.press.rawValue]
            add.onPerform = { [weak self] _ in
                guard let self else { return }
                popup.replaceMenu(with: picker)
            }
        }

        func addReaction(named name: String?, own: Bool = true, spokenTitle: Bool = false) {
            let button = MessageFixtures.reaction(title: "Synthetic reaction", description: "", reacted: own)
            button.attributes[.value] = .bool(own)
            if let name {
                button.children = [FakeNode(role: "AXImage", domClasses: Locators.emojiImage.classes,
                                            attributes: [.title: .string(spokenTitle ? "\(name) emoji" : ":\(name):")])]
            }
            reactionBar.children.append(button)
        }

        func cell(_ name: String, enabled: Bool = true) -> FakeNode {
            let cell = FakeNode(role: "AXCell", domClasses: Locators.emojiCell.classes, domID: "emoji-picker-\(name)",
                                attributes: [.enabled: .bool(enabled)])
            cell.actionNames = [UIAction.press.rawValue]
            return cell
        }

        func dismissPicker() {
            popup.dismiss()
            core.webArea.children = visibleRoots
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
        fixture.row.children.append(longer)
        fixture.search.onSet = { [weak fixture] attribute, value in
            guard let fixture, attribute == .value, value == .string("tada") else { return }
            fixture.search.attributes[attribute] = value
            fixture.row.children.append(exact)
        }
        exact.onPerform = { [weak fixture] _ in
            fixture?.addReaction(named: "tada", spokenTitle: true)
            fixture?.dismissPicker()
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
        fixture.row.children.append(longer)
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
        fixture.row.children.append(exact)
        exact.onPerform = { [weak fixture] _ in fixture?.dismissPicker() }
        let error = #expect(throws: RemoteError.self) { try fixture.run(timeout: 0.3) }
        #expect(error?.code == "reaction_unconfirmed")
        #expect(exact.performCalls == [.press])
    }

    @Test func refusesToPressWhenThePickerHidesTheMessage() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.row.children.append(exact)
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

    @Test func keepsTheVerifiedTargetWhenTheOwnedPickerHidesTheConversation() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.row.children = [exact]
        fixture.column.children = [exact]
        fixture.add.onPerform = { [weak fixture] _ in
            guard let fixture else { return }
            fixture.popup.replaceMenu(with: fixture.picker)
            fixture.core.webArea.children = [fixture.popup.modal, fixture.popup.backdrop]
        }
        exact.onPerform = { [weak fixture] _ in
            fixture?.addReaction(named: "tada")
            fixture?.dismissPicker()
        }
        #expect(try fixture.run().alreadyReacted == false)
        #expect(exact.performCalls == [.press])
        #expect(try fixture.run().alreadyReacted)
        #expect(exact.performCalls == [.press])
    }

    @Test func refusesDistinctMatchingCellsInTheRowAndColumn() throws {
        let fixture = try Fixture()
        let first = fixture.cell("tada")
        let second = fixture.cell("tada")
        fixture.row.children = [first]
        fixture.column.children = [second]
        let error = #expect(throws: RemoteError.self) { try fixture.run(timeout: 0.3) }
        #expect(error?.code == "ui_drift")
        #expect(first.performCalls.isEmpty && second.performCalls.isEmpty)
        #expect(fixture.popup.backdrop.performCalls == [.press])
    }

    @Test func refusesADisabledExactCell() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada", enabled: false)
        fixture.row.children = [exact]
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "ui_drift")
        #expect(exact.performCalls.isEmpty)
    }

    @Test func replacementPickerIsNeitherPressedNorDismissed() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.row.children = [exact]
        fixture.search.onSet = { [weak fixture] _, _ in
            guard let fixture else { return }
            let replacement = FakeNode(role: fixture.picker.role, domClasses: fixture.picker.domClasses,
                                       children: fixture.picker.children)
            fixture.popup.modal.children = [replacement]
        }
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "overlay_left_open")
        #expect(exact.performCalls.isEmpty)
        #expect(fixture.popup.backdrop.performCalls.isEmpty)
    }

    @Test func sameURLInAReplacementWebAreaDoesNotAuthorizeThePicker() throws {
        let fixture = try Fixture()
        let exact = fixture.cell("tada")
        fixture.row.children = [exact]
        let parent = try #require(fixture.core.window.children.first as? FakeNode)
        fixture.search.onSet = { [weak fixture, weak parent] _, _ in
            guard let web = fixture?.core.webArea else { return }
            parent?.children = [FakeNode(role: web.role, children: web.children, attributes: web.attributes)]
        }
        let error = #expect(throws: RemoteError.self) { try fixture.run() }
        #expect(error?.code == "overlay_left_open")
        #expect(exact.performCalls.isEmpty)
        #expect(fixture.popup.backdrop.performCalls.isEmpty)
    }
}
