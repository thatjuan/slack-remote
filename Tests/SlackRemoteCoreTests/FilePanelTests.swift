@testable import SlackRemoteCore
import Testing

struct FilePanelTests {
    @Test func selectsExactURLAndPressesOpenOnce() throws {
        let f = try UploadFixture()
        try f.attachFile()
        #expect(f.file.setCalls.count == 1)
        #expect(f.file.setCalls.first?.attribute == .selected)
        #expect(f.wrong.setCalls.isEmpty)
        #expect(f.open.performCalls == [.press])
        #expect(f.cancel.performCalls.isEmpty)
    }

    @Test func multipleSelectedRowsCancelWithoutOpening() throws {
        let f = try UploadFixture()
        f.wrong.attributes[.selected] = .bool(true)
        #expect(throws: RemoteError.self) { try f.attachFile() }
        #expect(f.open.performCalls.isEmpty)
        #expect(f.cancel.performCalls == [.press])
        #expect(Overlays.open(in: f.view.tree).isEmpty)
    }

    @Test func sheetThatWillNotCloseIsReported() throws {
        let f = try UploadFixture()
        f.wrong.attributes[.selected] = .bool(true)
        f.cancel.onPerform = nil
        do {
            try f.attachFile()
            Issue.record("Expected overlay_left_open")
        } catch RemoteError.overlayLeftOpen {
            #expect(f.cancel.performCalls == [.press])
            #expect(f.open.performCalls.isEmpty)
        }
    }

    @Test func interruptionCancelsBeforeOpening() throws {
        let f = try UploadFixture()
        f.view.tree.unwindOnSignal = true
        f.file.onSet = { _, _ in #expect(f.view.tree.requestInterruption()) }
        #expect(throws: SlackTree.Interruption.self) { try f.attachFile() }
        #expect(f.open.performCalls.isEmpty)
        #expect(f.cancel.performCalls == [.press])
        #expect(Overlays.open(in: f.view.tree).isEmpty)
    }
}
