import Foundation
import ApplicationServices
@testable import SlackRemoteCore
import Testing

struct SearchModalTests {
    @Test func refreshedAccessibilityNodesCanIdentifyTheSameElementWithoutADOMID() {
        let first = AXNode(AXUIElementCreateApplication(getpid()))
        let refreshed = AXNode(AXUIElementCreateApplication(getpid()))
        #expect(first.domID == nil)
        #expect(first !== refreshed)
        #expect(SearchPopup(node: first).matches(refreshed))
    }

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

    @Test func interruptionBeforeFirstPopupSnapshotWaitsForTheOwnedPopupAndItsBackdrop() throws {
        let fixture = try SearchModalFixture()
        var snapshotsAfterPress = 0
        var initiated = false
        let tree = SlackTree(refresh: {
            if initiated {
                snapshotsAfterPress += 1
                if snapshotsAfterPress == 2 { fixture.showPopup(backdropReady: false) }
                if snapshotsAfterPress == 5 { fixture.showPopup(backdropReady: true) }
            }
            return [fixture.window]
        })
        fixture.search.onPerform = { _ in
            initiated = true
            #expect(tree.requestInterruption())
        }
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated away from its verified start") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })

        #expect(throws: SlackTree.Interruption.self) {
            try SearchResults.restoring(start: fixture.destination, in: tree, navigator: navigator,
                                        keepOnSuccess: false) {
                try fixture.run(in: tree, onOpen: { Issue.record("Search did not own the popup before SIGINT") })
            }
        }
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: tree).isEmpty)
        #expect(try SlackWindow.currentWindow(in: tree).location.destination == fixture.destination)
    }

    @Test func interruptionAtTheOpenTraceWaitsForTheDismissControl() throws {
        let fixture = try SearchModalFixture()
        var interruptedSnapshots = 0
        var interrupted = false
        let tree = SlackTree(refresh: {
            if interrupted {
                interruptedSnapshots += 1
                if interruptedSnapshots == 3 { fixture.showPopup(backdropReady: true) }
            }
            return [fixture.window]
        })
        // A search popup can expose its field before the backdrop is accessible.
        fixture.search.onPerform = { _ in fixture.showPopup(backdropReady: false) }
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated away from its verified start") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })

        #expect(throws: SlackTree.Interruption.self) {
            try SearchResults.restoring(start: fixture.destination, in: tree, navigator: navigator,
                                        keepOnSuccess: false) {
                try fixture.run(in: tree, onOpen: {
                    interrupted = true
                    #expect(tree.requestInterruption())
                })
            }
        }
        #expect(fixture.submit.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: tree).isEmpty)
        #expect(try SlackWindow.currentWindow(in: tree).location.destination == fixture.destination)
    }

    @Test func interruptionRebuildsTheOwnedTreeWhenSlackExposesOnlyTheCloseButton() throws {
        let fixture = try SearchModalFixture()
        let close = FakeNode(role: "AXButton", domClasses: Locators.searchClose.classes)
        fixture.addCloseControl(close)
        fixture.search.onPerform = { _ in fixture.showPopup(backdropReady: false) }
        var rebuilds = 0
        fixture.tree.rebuildOwnedMode = { _ in
            rebuilds += 1
            fixture.showPopup(backdropReady: true, replaceAXNode: true)
        }
        let navigator = Navigator(openLink: { _ in Issue.record("Search navigated away from its verified start") },
                                  frontmostBundleID: { nil }, activate: { _ in }, secondsSinceUserInput: { .infinity })

        #expect(throws: SlackTree.Interruption.self) {
            try SearchResults.restoring(start: fixture.destination, in: fixture.tree, navigator: navigator,
                                        keepOnSuccess: false) {
                try fixture.run(onOpen: { #expect(fixture.tree.requestInterruption()) })
            }
        }
        #expect(rebuilds == 1)
        #expect(close.performCalls.isEmpty)
        #expect(fixture.backdrop.performCalls == [.press])
        #expect(Overlays.open(in: fixture.tree).isEmpty)
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
