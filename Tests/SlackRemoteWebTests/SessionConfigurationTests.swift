import Foundation
@testable import SlackRemoteWeb
import Testing

struct SessionConfigurationTests {
    @Test(arguments: [nil, "26.1"] as [String?])
    func safariUserAgent(version: String?) {
        let expectedVersion = version ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        #expect(SafariUserAgent.make(safariVersion: version) ==
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(expectedVersion) Safari/605.1.15")
    }

    @Test(arguments: [
        (["en-CA"], "en-CA,en;q=0.9"),
        (["fr-FR", "en-CA"], "fr-FR,fr;q=0.9"),
        (["en"], "en"),
        (["en", "fr-CA", "de"], "en,fr-CA;q=0.9"),
        ([], ""),
    ])
    func safariAcceptLanguage(preferred: [String], expected: String) {
        #expect(SafariUserAgent.acceptLanguage(preferred) == expected)
    }

    @Test func nativePostUsesSafariHeaders() throws {
        let url = try #require(URL(string: "https://app.slack.com/api/auth.test"))
        let request = makeNativePostRequest(url: url, form: [:], cookies: [])
        #expect(request.value(forHTTPHeaderField: "User-Agent") == SafariUserAgent.current)
        #expect(request.value(forHTTPHeaderField: "Accept-Language") ==
            SafariUserAgent.acceptLanguage(Locale.preferredLanguages))
    }

    @Test func decodesRedactedLocalConfig() throws {
        let sample = """
            {"teams":{"T0123ABCD":{"id":"T0123ABCD","name":"Acme","domain":"acme","url":"https://acme.slack.com/",
                "token":"[redacted]","user_id":"U0123ABCD","enterprise_id":null}}}
            """
        let config = try JSONDecoder().decode(LocalConfig.self, from: Data(sample.utf8))
        let team = try #require(config.teams["T0123ABCD"])
        #expect(team.id == "T0123ABCD")
        #expect(team.name == "Acme")
        #expect(team.url == "https://acme.slack.com/")
        #expect(team.token == "[redacted]")
        #expect(team.userID == "U0123ABCD")
    }
}
