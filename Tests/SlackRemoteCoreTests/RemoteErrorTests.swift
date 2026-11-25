import Foundation
@testable import SlackRemoteCore
import Testing

struct RemoteErrorTests {
    @Test func accessibilityErrorDescribesTheHostWhenKnown() throws {
        let host = HostApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty", path: "/Applications/Ghostty.app")
        let error = RemoteError.accessibilityNotTrusted(host: host)
        #expect(error.message == "Turn on Ghostty in System Settings › Privacy & Security › Accessibility, or run slack-remote doctor --grant.")
        #expect(error.code == "accessibility_not_trusted")
        #expect(error.exitStatus == 10)
        let details = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(error.details))
        #expect(details == [
            "hostApp": "Ghostty",
            "hostBundleId": "com.mitchellh.ghostty",
            "hostPath": "/Applications/Ghostty.app",
            "settingsUrl": Environment.accessibilitySettingsURL.absoluteString,
        ])

        let unknown = RemoteError.accessibilityNotTrusted(host: nil)
        #expect(unknown.message == "Turn on the app that runs this shell (your terminal, editor or agent app) in System Settings › Privacy & Security › Accessibility, or run slack-remote doctor --grant from it.")
        let unknownDetails = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(unknown.details))
        #expect(unknownDetails == ["settingsUrl": Environment.accessibilitySettingsURL.absoluteString])

        let unidentified = RemoteError.accessibilityNotTrusted(host: HostApp(name: "Terminal", bundleID: nil,
                                                                           path: "/Applications/Terminal.app"))
        let unidentifiedDetails = try JSONDecoder().decode([String: String].self,
                                                          from: JSONEncoder().encode(unidentified.details))
        #expect(unidentifiedDetails["hostApp"] == "Terminal")
        #expect(unidentifiedDetails["hostBundleId"] == nil)
    }
}
