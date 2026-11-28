import Foundation
import SlackRemoteCore
import Testing

struct ConfigTests {
    @Test func writesAndReplacesPrivateJSONAndRejectsWorldReadableFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let team = TeamID("T0AAAAAAA")!
        let destination = Destination(team: team, conversation: ConversationID("C0BBBBBBB")!)
        #expect(try Config.load(from: url) == nil)
        var config = Config()
        config.destinations["notes"] = destination
        try config.save(to: url)
        config.restrictWritesToDestinations = true
        try config.save(to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let loaded = try #require(try Config.load(from: url))
        #expect(loaded.destinations == ["notes": destination])
        #expect(loaded.restrictWritesToDestinations)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let destinations = try #require(json["destinations"] as? [String: [String: String]])
        #expect(destinations["notes"] == ["team": "T0AAAAAAA", "conversation": "C0BBBBBBB"])

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let error = #expect(throws: RemoteError.self) { try Config.load(from: url) }
        #expect(error?.code == "config_invalid")
    }

    @Test func loadsConfigWithAnAccountsKey() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let json = """
            {
              "accounts": [{"team": "T0AAAAAAA", "user": "U0DDDDDDD", "selfDM": "D0CCCCCCC"}],
              "destinations": {"notes": {"team": "T0AAAAAAA", "conversation": "C0BBBBBBB"}},
              "restrictWritesToDestinations": true
            }
            """
        try Data(json.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let config = try #require(try Config.load(from: url))
        #expect(config.destinations["notes"] == Destination(team: TeamID("T0AAAAAAA")!,
                                                           conversation: ConversationID("C0BBBBBBB")!))
        #expect(config.restrictWritesToDestinations)
    }

    @Test func allowlistMatchesExactTeamAndConversation() throws {
        var config = Config()
        config.restrictWritesToDestinations = true
        let conversation = ConversationID("C0BBBBBBB")!
        let permitted = Destination(team: TeamID("T0AAAAAAA")!, conversation: conversation)
        config.destinations["notes"] = permitted
        try config.requireWriteAllowed(to: permitted)
        let other = Destination(team: TeamID("T0EEEEEEE")!, conversation: conversation)
        let error = #expect(throws: RemoteError.self) { try config.requireWriteAllowed(to: other) }
        #expect(error?.code == "write_not_allowed")
    }
}
