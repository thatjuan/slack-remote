import Foundation
@testable import SlackRemoteCore
import Testing

struct SearchModalTests {
    @Test func appliesOnlyTheRequestedConversationFilter() throws {
        let fixture = try SearchModalFixture()
        try fixture.run()
        #expect(fixture.inFilter.performCalls == [.press, .press, .press])
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

    @MainActor
    @Test func interruptionBeforeSubmitClosesTheOwnedPopupBeforeAccessibilityIsRestored() throws {
        let fixture = try SearchModalFixture()
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: support) }
        var modeChanges: [Bool] = []
        let app = SlackApp(identity: ProcessIdentity(pid: 12345, launchDate: Date()), supportDirectory: support,
                           readWindows: { modeChanges.last == true ? [fixture.window] : [] },
                           setMode: { enabled in
            if !enabled {
                #expect(fixture.backdrop.performCalls == [.press])
                #expect(Overlays.open(in: fixture.tree).isEmpty)
            }
            modeChanges.append(enabled)
        })
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated away from its verified start") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })

        #expect(throws: SlackTree.Interruption.self) {
            try app.withTree(deadline: Date().addingTimeInterval(3)) { tree in
                fixture.didWriteQuery = { #expect(tree.requestInterruption()) }
                defer { fixture.didWriteQuery = nil }
                try SearchResults.restoring(start: fixture.destination, in: tree, navigator: navigator,
                                            keepOnSuccess: false) {
                    try fixture.run(in: tree)
                }
            }
        }
        #expect(modeChanges == [true, false])
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.clear.performCalls == [.press])
    }

    @Test func interruptionLeavesAReplacementSearchShapedPopupUntouched() throws {
        let fixture = try SearchModalFixture()
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated while a popup was open") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
        var replacement: (clear: FakeNode, backdrop: FakeNode)?
        let failure = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: fixture.destination, in: fixture.tree, navigator: navigator,
                                        keepOnSuccess: false) {
                try fixture.run(onOpen: {
                    replacement = fixture.replaceSearchPopup()
                    #expect(fixture.tree.requestInterruption())
                })
            }
        }
        #expect(failure?.code == "overlay_left_open")
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls.isEmpty)
        #expect(replacement?.clear.performCalls.isEmpty == true)
        #expect(replacement?.backdrop.performCalls.isEmpty == true)
    }

    @Test func interruptionStillClosesThePopupWhenClearingTheFieldFails() throws {
        let fixture = try SearchModalFixture()
        fixture.didWriteQuery = { #expect(fixture.tree.requestInterruption()) }
        fixture.clear.onPerform = { _ in throw RemoteError.axFailure(operation: "AXPress", code: -1) }
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated away from its verified start") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })
        let failure = #expect(throws: RemoteError.self) {
            try SearchResults.restoring(start: fixture.destination, in: fixture.tree, navigator: navigator,
                                        keepOnSuccess: false) { try fixture.run() }
        }
        #expect(failure?.code == "ax_failure")
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
    }
}
