import ArgumentParser
import SlackRemoteCore

struct Reply: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Reply in a verified Slack thread.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "The parent message's Slack timestamp.") var thread: String
    @Option(help: "Text to send.") var text: String
    @Flag(help: "Share the reply with the conversation.") var alsoSendToChannel = false
    @Flag(help: "Allow @channel, @here and @everyone mentions.") var allowBroadcast = false
    @Flag(help: "Show the plan without changing Slack.") var dryRun = false

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        let method: WriteMethod
        let sent = true
        let ts: String
        let thread: String
    }

    func validate() throws {
        try target.validate(requireDestination: true)
        guard MessageReader.isTimestamp(thread) else {
            throw ValidationError("--thread must be a Slack message timestamp.")
        }
    }

    func run() throws {
        let idle = WriteCommand.idleCheck(target)
        try WriteCommand.run("reply", text: text, allowBroadcast: allowBroadcast, options: options, target: target,
            preview: dryRun ? .reply(rootTs: thread, text: text, broadcast: alsoSendToChannel) : nil
        ) { view, tree, route, deadline in
            let pane = try ThreadView.open(view.destination, rootTs: thread, in: tree, deadline: deadline, requireIdle: idle)
            let sender = Sender(view: view, scope: .thread(pane), in: tree, requireIdle: idle)
            let receipt = try sender.send(text, alsoSendToChannel: alsoSendToChannel, deadline: deadline)
            return Result(team: view.destination.team.rawValue, conversation: view.destination.conversation.rawValue,
                          route: route, method: receipt.method, ts: receipt.ts, thread: thread)
        }
    }
}
