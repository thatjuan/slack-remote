import SlackRemoteCore
import Testing

struct HelperForwardingTests {
    @Test(arguments: ["help", "--help", "-h", "--version"])
    func keepsGlobalHelpAndVersionLocal(_ argument: String) {
        #expect(!HelperForwarding.shouldForward(arguments: [argument], noHelper: nil))
    }

    @Test func supportsOptOut() {
        #expect(!HelperForwarding.shouldForward(arguments: ["doctor"], noHelper: "1"))
        #expect(!HelperForwarding.shouldForward(arguments: [], noHelper: nil))
        #expect(HelperForwarding.shouldForward(arguments: ["doctor", "--grant"], noHelper: nil))
    }

    @Test(arguments: [["--file", "folder/a b.pdf"], ["--file=folder/a b.pdf"]])
    func rewritesOnlyFileOption(_ fileOption: [String]) throws {
        let rewritten = try #require(HelperForwarding.rewriteUpload(arguments:
            ["upload", "--dest", "notes"] + fileOption + ["--text", "caption", "--dry-run"]))
        #expect(rewritten.path == "folder/a b.pdf")
        #expect(rewritten.arguments == [
            "upload", "--dest", "notes", "--file", "/dev/fd/3", "--file-name", "a b.pdf",
            "--text", "caption", "--dry-run",
        ])
    }

    @Test func respectsOptionBoundaryAndDashPrefixedNames() {
        #expect(HelperForwarding.rewriteUpload(arguments: ["upload", "--", "--file=extra"]) == nil)
        #expect(HelperForwarding.rewriteUpload(arguments: ["upload", "--file=folder/-a"])?.arguments
                == ["upload", "--file", "/dev/fd/3", "--file-name=-a"])
        #expect(HelperForwarding.rewriteUpload(arguments: ["upload", "--file", "-"])?.path == "-")
    }
}
