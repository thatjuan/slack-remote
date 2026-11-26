import Foundation
@testable import SlackRemoteWeb
import Testing

struct SlackSessionTests {
    @Test(arguments: [("27.1", "27.1"), (nil, "18.0")] as [(String?, String)])
    func safariUserAgent(version: String?, expectedVersion: String) {
        #expect(SafariUserAgent.make(safariVersion: version) ==
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(expectedVersion) Safari/605.1.15")
    }

    @Test func decodesLocalConfig() throws {
        let json = """
            {"teams":{"T0123ABCD":{"id":"T0123ABCD","name":"Acme","domain":"acme",
            "url":"https://acme.slack.com/","token":"[redacted]","user_id":"U0123ABCD","enterprise_id":null}}}
            """
        let config = try JSONDecoder().decode(LocalConfig.self, from: Data(json.utf8))
        let team = try #require(config.teams["T0123ABCD"])
        #expect(team.id == "T0123ABCD")
        #expect(team.name == "Acme")
        #expect(team.url == "https://acme.slack.com/")
        #expect(team.token == "[redacted]")
        #expect(team.userID == "U0123ABCD")
    }
}
