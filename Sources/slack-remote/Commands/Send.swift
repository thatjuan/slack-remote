import ArgumentParser
import SlackRemoteCore

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Send text to a verified Slack conversation.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Text to send.") var text: String
    @Flag(help: "Allow @channel, @here and @everyone mentions.") var allowBroadcast = false
    @Flag(help: "Show the plan without changing Slack.") var dryRun = false

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        let method: WriteMethod
        let sent = true
        let ts: String
    }

    func validate() throws { try target.validate(requireDestination: true) }

    func run() throws {
        try WriteCommand.run("send", text: text, allowBroadcast: allowBroadcast, options: options,
                             target: target, primaryComposer: true,
                             preview: dryRun ? .send(text) : nil) { view, tree, route, deadline in
            let sender = Sender(view: view, in: tree, requireIdle: WriteCommand.idleCheck(target))
            let receipt = try sender.send(text, deadline: deadline)
            return Result(team: view.destination.team.rawValue, conversation: view.destination.conversation.rawValue,
                          route: route, method: receipt.method, ts: receipt.ts)
        }
    }
}
