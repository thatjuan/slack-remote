import ArgumentParser
import SlackRemoteCore

struct React: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add one emoji reaction to a verified Slack message.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Slack timestamp of the message to react to.") var ts: String
    @Option(help: "Emoji short name, without colons.") var emoji: String
    @Option(help: "Root message timestamp when targeting an item in a thread.") var thread: String?
    @Flag(help: "Show the plan without changing Slack.") var dryRun = false

    func validate() throws {
        try target.validate(requireDestination: true)
        guard MessageReader.isTimestamp(ts) else { throw ValidationError("--ts must be a Slack message timestamp.") }
        if let thread, !MessageReader.isTimestamp(thread) {
            throw ValidationError("--thread must be a Slack message timestamp.")
        }
    }

    func run() throws {
        let idle = WriteCommand.idleCheck(target)
        try WriteCommand.run("react", options: options, target: target,
            preview: dryRun ? .react(ts: ts, thread: thread) : nil, validateInput: {
                guard MessageText.isEmojiName(emoji) else {
                    throw RemoteError.unsafeText(reason: "invalid_emoji_name")
                }
            }
        ) { view, tree, _, deadline in
            let scope: MessageScope
            if let thread {
                let pane = try ThreadView.open(view.destination, rootTs: thread, in: tree, deadline: deadline, requireIdle: idle)
                scope = .thread(pane)
            } else {
                scope = .primary
            }
            return try Reactions.add(emoji, to: ts, in: view, scope: scope, tree: tree, deadline: deadline, requireIdle: idle)
        }
    }
}
