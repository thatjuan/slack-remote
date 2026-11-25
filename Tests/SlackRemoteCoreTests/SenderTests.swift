import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct SenderTests {
    private let text = "example\nmessage"

    private func fixture() throws -> ComposerFixture {
        let fixture = try ComposerFixture()
        fixture.scriptWrite(accepting: .selectedText)
        fixture.appendMessage(0, text: "example message")
        return fixture
    }

    @Test func confirmsNewMessageAndPressesOnce() throws {
        let fixture = try fixture()
        fixture.scriptPress(message: "example message")
        let result = try fixture.sender().send(text, deadline: Date().addingTimeInterval(2))
        #expect(result.ts == "1700000001.000100")
        #expect(result.method == .selectedText)
        #expect(fixture.send.performCalls == [.press])
        #expect(try fixture.composer().state() == .empty)
    }

    @Test func destinationChangePreventsPress() throws {
        let fixture = try fixture()
        let sender = fixture.sender {
            fixture.webArea.attributes[.url] = .string("https://app.slack.com/client/T0AAAAAAA/D0CCCCCCC")
        }
        let error = #expect(throws: WriteFailure.self) {
            try sender.send(text, deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "destination_mismatch")
        #expect(error?.draftLeft == nil)
        #expect(fixture.send.performCalls.isEmpty)
    }

    @Test func changedComposerTextPreventsPress() throws {
        let fixture = try fixture()
        let sender = fixture.sender { fixture.show(.text("changed")) }
        let error = #expect(throws: WriteFailure.self) {
            try sender.send(text, deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "write_unverified")
        #expect(error?.draftLeft == true)
        #expect(fixture.send.performCalls.isEmpty)
    }

    @Test func disabledSendButtonPreventsPress() throws {
        let fixture = try fixture()
        let sender = fixture.sender { fixture.disableSend() }
        let error = #expect(throws: WriteFailure.self) {
            try sender.send(text, deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "write_unverified")
        #expect(error?.draftLeft == true)
        #expect(fixture.send.performCalls.isEmpty)
    }

    @Test func blockingDialogPreventsPress() throws {
        let fixture = try fixture()
        let sender = fixture.sender {
            fixture.webArea.children.append(FakeNode(role: "AXGroup", subrole: "AXApplicationDialog"))
        }
        let error = #expect(throws: WriteFailure.self) {
            try sender.send(text, deadline: Date().addingTimeInterval(2))
        }
        #expect(error?.error.code == "ui_blocked")
        #expect(error?.draftLeft == true)
        #expect(fixture.send.performCalls.isEmpty)
    }

    @Test func unchangedComposerReportsSendNotPerformed() throws {
        let fixture = try fixture()
        let error = #expect(throws: RemoteError.self) {
            try fixture.sender().send(text, deadline: Date().addingTimeInterval(0.2))
        }
        #expect(error?.code == "send_not_performed")
        #expect(fixture.send.performCalls == [.press])
    }

    @Test func emptyComposerWithoutNewMessageReportsSendUnconfirmed() throws {
        let fixture = try fixture()
        fixture.scriptPress(message: nil)
        let error = #expect(throws: WriteFailure.self) {
            try fixture.sender().send(text, deadline: Date().addingTimeInterval(0.2))
        }
        #expect(error?.error.code == "send_unconfirmed")
        #expect(error?.draftLeft == false)
        #expect(fixture.send.performCalls == [.press])
    }

    @Test func differentNewMessageDoesNotConfirmSend() throws {
        let fixture = try fixture()
        fixture.send.onPerform = { [weak fixture] _ in
            fixture?.show(.empty)
            fixture?.list.children.append(MessageFixtures.message(1, sender: "Someone else",
                                                                   sections: [[MessageFixtures.text("different")]]))
        }
        let error = #expect(throws: WriteFailure.self) {
            try fixture.sender().send(text, deadline: Date().addingTimeInterval(0.2))
        }
        #expect(error?.error.code == "send_unconfirmed")
        #expect(fixture.send.performCalls == [.press])
    }
}
