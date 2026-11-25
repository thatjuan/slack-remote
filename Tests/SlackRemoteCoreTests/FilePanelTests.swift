import AppKit
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

    @Test func checksTheSelectedURLAgainImmediatelyBeforeOpen() throws {
        let f = try UploadFixture()
        let panel = FilePanel(tree: f.view.tree, destination: f.view.view.destination, requireIdle: {},
                             requireAccount: { _ in
            f.file.attributes[.selected] = .bool(false)
            f.wrong.attributes[.selected] = .bool(true)
        })
        #expect(throws: RemoteError.self) {
            try panel.attach(f.staged, deadline: Date().addingTimeInterval(0.5),
                             opening: { try f.attach.perform(.press) }, openingFile: {})
        }
        #expect(f.open.performCalls.isEmpty)
        #expect(f.cancel.performCalls == [.press])
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

    @Test func pasteboardRestoresAllTypesOnFailure() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let text = NSPasteboardItem()
        let fixtureType = NSPasteboard.PasteboardType("com.slack-remote.fixture")
        let bytes = Data([0, 1, 2])
        text.setString("synthetic text", forType: .string)
        text.setData(bytes, forType: fixtureType)
        let second = NSPasteboardItem()
        second.setString("synthetic second item", forType: .string)
        #expect(board.writeObjects([text, second]))

        struct Failure: Error {}
        let f = try UploadFixture()
        #expect(throws: Failure.self) {
            try FilePaste.withURL(f.staged, in: board) { requireExactFile in
                try requireExactFile()
                throw Failure()
            }
        }
        let items = try #require(board.pasteboardItems)
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "synthetic text")
        #expect(items.first?.data(forType: fixtureType) == bytes)
        #expect(items.last?.string(forType: .string) == "synthetic second item")
    }

    @Test func pasteboardLeavesAConcurrentCopyAlone() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.clearContents()
        let f = try UploadFixture()
        try FilePaste.withURL(f.staged, in: board) { requireExactFile in
            _ = board.clearContents()
            #expect(board.setString("synthetic replacement", forType: .string))
            #expect(throws: RemoteError.self) { try requireExactFile() }
        }
        #expect(board.string(forType: .string) == "synthetic replacement")
    }
}
