import SlackRemoteCore
import Testing

struct FileNameTests {
    @Test(arguments: ["", ".hidden", "../invalid", "folder/name", "folder\\name", "line\nbreak", "file:name"])
    func rejectsInvalidNames(_ name: String) {
        let error = #expect(throws: RemoteError.self) { try FileName.validate(name) }
        guard case .fileRejected(let reason)? = error else {
            Issue.record("Expected file_rejected")
            return
        }
        #expect(reason == "invalid_name")
    }

    @Test func acceptsVisibleNames() throws {
        try FileName.validate("my résumé.pdf")
    }
}
