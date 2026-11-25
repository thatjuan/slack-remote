import Foundation
import SlackRemoteCore
import Testing

struct DryRunTests {
    @Test(arguments: [
        DryRun.Operation.open, .draftSet("synthetic"), .draftClear("synthetic"), .send("synthetic"),
    ])
    func previewsEachOperationWithoutAXMutations(_ operation: DryRun.Operation) throws {
        let fixture = try ComposerFixture()
        if case .draftClear = operation { fixture.show(.text("synthetic")) }
        let result = try DryRun.preview(operation, destination: fixture.view.destination, user: nil,
            preference: .auto, config: nil, in: fixture.tree, deadline: .distantFuture)
        #expect(result.atDestination)
        let nodes = fixture.window.descendants().compactMap { $0 as? FakeNode }
        #expect(nodes.allSatisfy { $0.setCalls.isEmpty && $0.performCalls.isEmpty })

        let other = Destination(team: fixture.view.destination.team, conversation: ConversationID("D0CCCCCCC")!)
        let away = try DryRun.preview(operation, destination: other, user: nil,
            preference: .auto, config: nil, in: fixture.tree, deadline: .distantFuture)
        #expect(!away.atDestination)
        #expect(away.plan.first == "navigate via deep_link_channel")
        #expect(away.composer == .unknown)
        #expect(nodes.allSatisfy { $0.setCalls.isEmpty && $0.performCalls.isEmpty })
    }

    @Test func rejectsVisibleDraftWithoutMutation() throws {
        let fixture = try ComposerFixture()
        fixture.show(.text("different"))
        let error = #expect(throws: RemoteError.self) {
            try DryRun.preview(.send("synthetic"), destination: fixture.view.destination, user: nil,
                preference: .auto, config: nil, in: fixture.tree, deadline: .distantFuture)
        }
        #expect(error?.code == "draft_conflict")
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(fixture.send.performCalls.isEmpty)
    }

    @Test func rejectsDisabledSendForAMatchingDraft() throws {
        let fixture = try ComposerFixture()
        fixture.show(.text("synthetic"))
        fixture.disableSend()
        let error = #expect(throws: RemoteError.self) {
            try DryRun.preview(.send("synthetic"), destination: fixture.view.destination, user: nil,
                preference: .auto, config: nil, in: fixture.tree, deadline: .distantFuture)
        }
        #expect(error?.code == "write_unverified")
        #expect(fixture.send.performCalls.isEmpty)
    }
}
