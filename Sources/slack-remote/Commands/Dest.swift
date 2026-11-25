import ArgumentParser
import SlackRemoteCore

struct Dest: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Manage named Slack destinations.",
                                                    subcommands: [Add.self, List.self])

    private struct Result: Encodable {
        let destinations: [String: Destination]
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create or replace a named destination.")

        @OptionGroup var options: CommandOptions
        @Argument(help: "Name with 1–32 lowercase letters, digits, underscores or hyphens.") var name: String
        @Option(help: "Slack workspace ID.", transform: { value in
            guard let team = TeamID(value) else { throw ValidationError("Expected a Slack team ID.") }
            return team
        }) var team: TeamID
        @Option(help: "Slack conversation ID.", transform: { value in
            guard let channel = ConversationID(value) else { throw ValidationError("Expected a Slack conversation ID.") }
            return channel
        }) var channel: ConversationID

        func validate() throws {
            guard Config.isValidName(name) else { throw ValidationError("Invalid destination name.") }
        }

        func run() throws {
            try CommandSupport.runLocal("dest add", options: options) {
                var config = try Config.load() ?? Config()
                config.destinations[name] = Destination(team: team, conversation: channel)
                try config.save()
                return Result(destinations: config.destinations)
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List configured destinations.")

        @OptionGroup var options: CommandOptions

        func run() throws {
            try CommandSupport.runLocal("dest list", options: options) {
                Result(destinations: try Config.load()?.destinations ?? [:])
            }
        }
    }
}
