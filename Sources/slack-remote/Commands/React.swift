import ArgumentParser
import SlackRemoteCore

/// Parses an emoji reaction addressed by the message's own timestamp.
struct React: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add an emoji reaction to a Slack message.")

    @OptionGroup var options: WriteOptions
    @Option(help: "The Slack message timestamp.", transform: writeTimestamp) var ts: String
    @Option(help: "Emoji name without colons.") var emoji: String

    func run() throws {
        let request = ReactRequest(target: try options.destination(), ts: ts, emoji: emoji, dryRun: options.dryRun)
        throw ExitCode(HelperClient.call(command: "react", operation: .react(request), timeout: options.command.timeout))
    }
}
