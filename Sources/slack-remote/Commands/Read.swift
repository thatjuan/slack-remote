import ArgumentParser
import SlackRemoteCore

/// Parses a conversation or thread read.
struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read Slack conversation or thread messages.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Thread parent's Slack timestamp.") var thread: String?
    @Option(help: "Return messages strictly newer than this Slack timestamp.") var since: String?
    @Option(help: "Return messages strictly older than this Slack timestamp.") var until: String?
    @Option(help: "Maximum messages to return, from 1 to 2,000.") var limit = 50
    @Flag(help: "Return the messages collected before the deadline.") var allowPartial = false

    func validate() throws {
        try target.validate(requireDestination: true)
        try CommandSupport.validateLimit(limit, maximum: 2000)
        for (name, timestamp) in [("thread", thread), ("since", since), ("until", until)] {
            if let timestamp, !SlackTimestamp.isValid(timestamp) {
                throw ValidationError("--\(name) must be a Slack timestamp, for example 1700000000.000100.")
            }
        }
    }

    func run() throws {
        try CommandSupport.call("read", timeout: options.timeout) {
            let destination = try target.requireDestination(using: Config.load())
            return .read(.init(destination: destination, thread: thread, since: since, until: until,
                               limit: limit, allowPartial: allowPartial))
        }
    }
}
