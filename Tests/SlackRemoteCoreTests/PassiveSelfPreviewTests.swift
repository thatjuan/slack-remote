import Foundation
@testable import SlackRemoteCore
import Testing

struct PassiveSelfPreviewTests {
    @Test func exactPreviewPreservesDraftGuards() throws {
        let fixture = try SelfPreviewFixture()
        let deadline = Date().addingTimeInterval(2)
        let view = try SlackWindow.verifyPrimaryWrite(fixture.destination, in: fixture.tree, config: fixture.config)
        let plan = try DryRun.preview(.draftSet("Synthetic draft"), destination: fixture.destination,
                                      user: nil, preference: .auto, config: fixture.config,
                                      in: fixture.tree, deadline: deadline)
        #expect(plan.account == .verified)
        #expect(plan.composer == .empty)
        #expect(fixture.editor.setCalls.isEmpty)

        fixture.editor.onSet = { [weak fixture] attribute, value in
            if attribute == .value, case .string(let text) = value { fixture?.setDraft(text) }
        }
        let composer = Composer(view: view, in: fixture.tree, requireIdle: {})
        #expect(try composer.write("Synthetic draft", deadline: deadline) == .value)
        #expect(try composer.write("Synthetic draft", deadline: deadline) == .existing)
        let different = #expect(throws: RemoteError.self) { try composer.write("Different", deadline: deadline) }
        let wrongClear = #expect(throws: RemoteError.self) { try composer.clear(expecting: "Different", deadline: deadline) }
        #expect(different?.code == "draft_conflict")
        #expect(wrongClear?.code == "draft_conflict")
        #expect(fixture.editor.string(.value) == "Synthetic draft")
        #expect(try composer.clear(expecting: "Synthetic draft", deadline: deadline))
        #expect(try composer.state() == .empty)
        #expect(fixture.editor.setCalls.count == 2)
        #expect(fixture.send.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls.isEmpty)
    }

    enum Change: CaseIterable {
        case modal, sheet, extraBackdrop, nativeDialog, extraControl, focus, stalePreview, account, exactURL, editorValue
    }

    @Test(arguments: Change.allCases)
    func refusesChangedOrUnprovenPreview(_ change: Change) throws {
        let fixture = try SelfPreviewFixture()
        let view = try SlackWindow.verifyPrimaryWrite(fixture.destination, in: fixture.tree, config: fixture.config)
        switch change {
        case .modal: fixture.web.children.append(FakeNode(role: "AXGroup", domClasses: [Locators.modalContent]))
        case .sheet: fixture.window.children.append(FakeNode(role: "AXSheet"))
        case .extraBackdrop: fixture.web.children.append(FakeNode(role: "AXGroup", domClasses: Locators.modalOverlay.classes))
        case .nativeDialog: fixture.web.children.append(FakeNode(role: "AXGroup", subrole: "AXApplicationDialog"))
        case .extraControl: fixture.popup.children.append(FakeNode(role: "AXButton"))
        case .focus: fixture.backdrop.attributes[.focused] = .bool(true)
        case .stalePreview:
            fixture.backdrop.children = [FakeNode(role: "AXGroup", domClasses: fixture.popup.domClasses,
                                                  children: fixture.popup.children, attributes: fixture.popup.attributes)]
        case .account: fixture.row.domClasses.removeAll { $0 == Locators.selfDM }
        case .exactURL:
            fixture.web.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/D0CCCCCCC/other")
        case .editorValue: fixture.editor.attributes[.value] = .string("Unsaved text")
        }
        let composer = Composer(view: view, in: fixture.tree, requireIdle: {})
        let error = #expect(throws: RemoteError.self) {
            try composer.write("Synthetic draft", deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "ui_blocked")
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(fixture.send.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls.isEmpty)
    }

    @Test func existingDistinctDraftAndUnconfiguredAccountRefuseWrites() throws {
        let fixture = try SelfPreviewFixture()
        fixture.setDraft("Existing draft")
        let unconfigured = #expect(throws: RemoteError.self) {
            try SlackWindow.verifyPrimaryWrite(fixture.destination, in: fixture.tree, config: nil)
        }
        #expect(unconfigured?.code == "ui_blocked")
        let view = try SlackWindow.verifyPrimaryWrite(fixture.destination, in: fixture.tree, config: fixture.config)
        let composer = Composer(view: view, in: fixture.tree, requireIdle: {})
        let deadline = Date().addingTimeInterval(2)
        let write = #expect(throws: RemoteError.self) { try composer.write("Synthetic draft", deadline: deadline) }
        let clear = #expect(throws: RemoteError.self) { try composer.clear(expecting: "Synthetic draft", deadline: deadline) }
        #expect(write?.code == "draft_conflict")
        #expect(clear?.code == "draft_conflict")
        #expect(fixture.editor.string(.value) == "Existing draft")
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(fixture.send.performCalls.isEmpty)
    }
}
