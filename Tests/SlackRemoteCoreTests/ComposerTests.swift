import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct ComposerTests {
    @Test func readsEmptyTextAndPendingContent() throws {
        let fixture = try ComposerFixture()
        let composer = fixture.composer()
        #expect(try composer.state() == .empty)
        fixture.show(.text("example\n"))
        #expect(try composer.state() == .text("example"))
        fixture.show(.pendingContent)
        #expect(try composer.state() == .pendingContent)
    }

    @Test func writesWithSelectedText() throws {
        let fixture = try ComposerFixture()
        fixture.scriptWrite(accepting: .selectedText)
        let composer = fixture.composer()
        #expect(try composer.write("example", deadline: Date().addingTimeInterval(2)) == .selectedText)
        #expect(try composer.state() == .text("example"))
        #expect(fixture.editor.setCalls.map(\.attribute) == [.focused, .selectedText])
    }

    @Test func fallsBackToValueOnlyWhenStillEmpty() throws {
        let fixture = try ComposerFixture()
        fixture.scriptWrite(accepting: .value)
        let composer = fixture.composer()
        #expect(try composer.write("example", deadline: Date().addingTimeInterval(5)) == .value)
        #expect(fixture.editor.setCalls.map(\.attribute) == [.focused, .selectedText, .value])
    }

    @Test func leavesDifferentDraftUntouched() throws {
        let fixture = try ComposerFixture()
        fixture.show(.text("other"))
        let composer = fixture.composer()
        let error = #expect(throws: RemoteError.self) {
            try composer.write("example", deadline: Date().addingTimeInterval(2))
        }
        guard case .draftConflict(let length)? = error else {
            Issue.record("Expected draft_conflict")
            return
        }
        #expect(length == 5)
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(try composer.state() == .text("other"))
    }

    @Test func reusesIdenticalDraft() throws {
        let fixture = try ComposerFixture()
        fixture.show(.text("example\n"))
        #expect(try fixture.composer().write("example", deadline: Date().addingTimeInterval(2)) == .existing)
        #expect(fixture.editor.setCalls.isEmpty)
    }

    @Test func stopsOnDifferentReadBack() throws {
        let fixture = try ComposerFixture()
        fixture.scriptWrite(accepting: .selectedText) { _ in "changed" }
        let error = #expect(throws: WriteFailure.self) {
            try fixture.composer().write("example", deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "write_unverified")
        #expect(error?.draftLeft == true)
        #expect(fixture.editor.setCalls.map(\.attribute) == [.focused, .selectedText])
    }

    @Test func reportsWriteFailedWhenNeitherMethodWorks() throws {
        let fixture = try ComposerFixture()
        fixture.scriptWrite(accepting: nil)
        let error = #expect(throws: WriteFailure.self) {
            try fixture.composer().write("example", deadline: Date().addingTimeInterval(6))
        }
        #expect(error?.error.code == "write_failed")
        #expect(error?.draftLeft == false)
        #expect(fixture.editor.setCalls.map(\.attribute) == [.focused, .selectedText, .value])
    }

    @Test func clearRefusesDifferentDraft() throws {
        let fixture = try ComposerFixture()
        fixture.show(.text("other"))
        let composer = fixture.composer()
        let error = #expect(throws: RemoteError.self) {
            try composer.clear(expecting: "example", deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.code == "draft_conflict")
        #expect(fixture.editor.setCalls.isEmpty)
        #expect(try composer.state() == .text("other"))
    }
}
