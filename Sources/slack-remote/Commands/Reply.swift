import ArgumentParser
import SlackRemoteCore

/// Parses a reply to a specific thread root.
struct Reply: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Post a reply to a Slack thread.")

    @OptionGroup var options: WriteOptions
    @Option(help: "The thread root's Slack message timestamp.", transform: writeTimestamp) var thread: String
    @Option(help: "Reply text.") var text: String
    @Flag(help: "Also share the reply in the main conversation.") var alsoSendToChannel = false
    @Flag(help: "Allow here, channel and everyone mentions.") var allowBroadcast = false

    func run() throws {
        let request = ReplyRequest(target: try options.destination(), thread: thread, text: text,
                                   alsoSendToChannel: alsoSendToChannel, allowBroadcast: allowBroadcast,
                                   dryRun: options.dryRun)
        throw ExitCode(HelperClient.call(command: "reply", operation: .reply(request), timeout: options.command.timeout))
    }
}
