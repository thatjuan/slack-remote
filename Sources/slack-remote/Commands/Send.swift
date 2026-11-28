import ArgumentParser
import SlackRemoteCore

/// Parses a message to post in a Slack conversation.
struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Post a message to a Slack conversation.")

    @OptionGroup var options: WriteOptions
    @Option(help: "Message text.") var text: String
    @Flag(help: "Allow here, channel and everyone mentions.") var allowBroadcast = false

    func run() throws {
        let request = SendRequest(target: try options.destination(), text: text,
                                  allowBroadcast: allowBroadcast, dryRun: options.dryRun)
        throw ExitCode(HelperClient.call(command: "send", operation: .send(request), timeout: options.command.timeout))
    }
}
