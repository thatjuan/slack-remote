import Foundation
import SlackRemoteCore
import Testing

@MainActor
struct OverlaysTests {
    private enum BodyError: Error { case expected }

    @Test func existingModalOrSheetBlocksAndIsNeverClosed() throws {
        let fixture = try ComposerFixture()
        let overlay = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
        fixture.webArea.children = [overlay, FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])]
        fixture.window.children.append(FakeNode(role: "AXSheet"))
        #expect(Overlays.open(in: fixture.tree) == [.modal, .sheet])
        let error = #expect(throws: RemoteError.self) {
            try Overlays.withModal(in: fixture.tree, deadline: .distantFuture,
                                   opening: { Issue.record("Opened over a pre-existing overlay") }) { _ in }
        }
        #expect(error?.code == "ui_blocked")
        #expect(overlay.performCalls.isEmpty)
    }

    @Test func closesOwnedModalWhenBodyThrows() throws {
        let fixture = try ComposerFixture()
        let primary = fixture.webArea.children
        let overlay = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
        let modal = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])
        overlay.onPerform = { _ in fixture.webArea.children = primary }
        #expect(throws: BodyError.expected) {
            try Overlays.withModal(in: fixture.tree, deadline: Date().addingTimeInterval(1), opening: {
                fixture.webArea.children = [overlay, modal]
            }) { _ in throw BodyError.expected }
        }
        #expect(overlay.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
        #expect(fixture.webArea.all(Locators.primaryView).count == 1)
    }

    @Test func reportsModalThatDidNotClose() throws {
        let fixture = try ComposerFixture()
        let overlay = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
        let modal = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])
        let error = #expect(throws: RemoteError.self) {
            try Overlays.withModal(in: fixture.tree, deadline: Date().addingTimeInterval(0.25), opening: {
                fixture.webArea.children = [overlay, modal]
            }) { _ in }
        }
        #expect(error?.code == "overlay_left_open")
        #expect(overlay.performCalls == [.press])
    }

    @Test func closesModalWhenOpeningReportedAnErrorAfterPress() throws {
        let fixture = try ComposerFixture()
        let primary = fixture.webArea.children
        let overlay = FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes)
        let modal = FakeNode(role: "AXGroup", domClasses: [Locators.modalContent])
        overlay.onPerform = { _ in fixture.webArea.children = primary }
        #expect(throws: BodyError.expected) {
            try Overlays.withModal(in: fixture.tree, deadline: Date().addingTimeInterval(1), opening: {
                fixture.webArea.children = [overlay, modal]
                throw BodyError.expected
            }) { _ in Issue.record("A failed opening must never enter the modal body") }
        }
        #expect(overlay.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }
}
