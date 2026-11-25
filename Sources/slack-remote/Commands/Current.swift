import ArgumentParser
import SlackRemoteCore

struct Current: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Report Slack's current view.")

    @OptionGroup var options: CommandOptions

    private struct Result: Encodable {
        let view: String
        let team: String
        var conversation: String?
        var kind: ConversationID.Kind?
        var trailing: [String]?
        var path: [String]?
    }

    func run() throws {
        try CommandSupport.run("current", options: options) { _, tree, _ in
            let client = try SlackWindow.currentWindow(in: tree)
            _ = try client.window.one(Locators.webArea)
            switch client.location {
            case .conversation(let destination, let trailing):
                return Result(view: "conversation", team: destination.team.rawValue,
                              conversation: destination.conversation.rawValue, kind: destination.conversation.kind,
                              trailing: trailing)
            case .other(let team, let path):
                return Result(view: "other", team: team.rawValue, path: path)
            case .notClient:
                throw RemoteError.slackNotReady
            }
        }
    }
}
