import Foundation
@testable import SlackRemoteCore
import Testing

struct UploaderTests {
    @Test func occupiedComposerLeavesAttachUntouched() throws {
        for state in [ComposerState.text("synthetic draft"), .pendingContent] {
            let f = try UploadFixture()
            f.composer.show(state)
            do {
                _ = try f.upload()
                Issue.record("Expected draft_conflict")
            } catch RemoteError.draftConflict {
                #expect(f.attach.performCalls.isEmpty)
                #expect(f.composer.editor.setCalls.isEmpty)
            }
        }
    }

    @Test func unexpectedPendingFileIsRemovedWithoutSending() throws {
        let f = try UploadFixture()
        f.pendingName = "different.txt"
        do {
            _ = try f.upload()
            Issue.record("Expected write_unverified")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "write_unverified")
            #expect(failure.pendingFileLeft == false)
            #expect(f.remove.performCalls == [.press])
            #expect(f.composer.send.performCalls.isEmpty)
        }
    }

    @Test func reportsWhenAFileCannotBeRemoved() throws {
        let f = try UploadFixture()
        f.pendingName = "different.txt"
        f.remove.actionNames = []
        do {
            _ = try f.upload()
            Issue.record("Expected write_unverified")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "write_unverified")
            #expect(failure.pendingFileLeft == true)
            #expect(f.composer.send.performCalls.isEmpty)
        }
    }

    @Test func finalConversationChangePreventsSend() throws {
        let f = try UploadFixture()
        var afterOpen = 0
        let tree = SlackTree(refresh: {
            if !f.open.performCalls.isEmpty {
                afterOpen += 1
                // Sheet closure, pending-file read-back, and message baseline precede the final gate.
                if afterOpen == 4 { f.view.webArea.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/D0CCCCCCC") }
            }
            return [f.view.window]
        })
        do {
            _ = try f.upload(tree: tree)
            Issue.record("Expected destination_mismatch")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "destination_mismatch")
            #expect(failure.pendingFileLeft == true)
            #expect(f.composer.send.performCalls.isEmpty)
            #expect(f.remove.performCalls.isEmpty)
        }
    }

    @Test func finalThreadRootChangePreventsSend() throws {
        let thread = try ThreadFixture()
        let f = try UploadFixture(thread: thread)
        var afterOpen = 0
        let tree = SlackTree(refresh: {
            if !f.open.performCalls.isEmpty {
                afterOpen += 1
                if afterOpen == 4 {
                    thread.list.children.compactMap { $0 as? FakeNode }.forEach {
                        $0.domID = $0.domID?.replacingOccurrences(of: ThreadFixture.root, with: ThreadFixture.otherRoot)
                    }
                }
            }
            return [f.view.window]
        })
        do {
            _ = try f.upload(tree: tree)
            Issue.record("Expected thread identity failure")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "ui_drift")
            #expect(f.composer.send.performCalls.isEmpty)
            #expect(f.remove.performCalls.isEmpty)
        }
    }

    @Test func noNewMessageIsTerminal() throws {
        let f = try UploadFixture()
        f.composer.send.onPerform = { [weak f] _ in f?.composer.show(.empty) }
        do {
            _ = try f.upload()
            Issue.record("Expected upload_unconfirmed")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "upload_unconfirmed")
            #expect(f.composer.send.performCalls == [.press])
            #expect(f.remove.performCalls.isEmpty)
        }
    }

    @Test func sendsOneFileWithTextOnce() throws {
        let f = try UploadFixture()
        f.composer.send.onPerform = { [weak f] _ in f?.appearSent(text: "synthetic caption") }
        let receipt = try f.upload(text: "synthetic caption")
        #expect(receipt.attachMethod == .filePanel)
        #expect(f.composer.send.performCalls == [.press])
        #expect(f.remove.performCalls.isEmpty)
    }

    @Test func rejectsDifferentNameOnSentAttachment() throws {
        let f = try UploadFixture()
        f.composer.send.onPerform = { [weak f] _ in f?.appearSent(text: nil, name: "other.txt") }
        do {
            _ = try f.upload()
            Issue.record("Expected upload_unconfirmed")
        } catch let failure as WriteFailure {
            #expect(failure.error.code == "upload_unconfirmed")
            #expect(f.composer.send.performCalls == [.press])
        }
    }
}
