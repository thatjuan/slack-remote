import ArgumentParser
import Foundation
import SlackRemoteCore

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read rendered messages or page through conversation history.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Keep this many of the newest rendered messages.") var limit: Int?
    @Flag(help: "Page through older messages in the requested conversation.") var history = false
    @Option(help: "Return messages newer than this Slack timestamp.") var since: String?
    @Option(help: "Maximum messages to collect, up to 2,000 (default: 200).") var maxMessages: Int?
    @Option(help: "Maximum snapshots to collect (default: 50).") var maxPages: Int?
    @Flag(help: "Return available messages if history stalls or reaches its deadline.") var allowPartial = false

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        var scope = "rendered"
        var complete = false
        var stopReason = StopReason.limit
        var pages = 0
        var oldestTs: String?
        var newestTs: String?
        var scrollRestored: Bool?
        let readAt: String
        let skippedItems: Int
        let messages: [Message]
    }

    func validate() throws {
        try target.validate(requireDestination: history)
        if let limit, limit < 0 {
            throw ValidationError("--limit must be zero or greater.")
        }
        if history && limit != nil { throw ValidationError("Use --max-messages with --history.") }
        if !history && (since != nil || maxMessages != nil || maxPages != nil || allowPartial) {
            throw ValidationError("--since, --max-messages, --max-pages and --allow-partial require --history.")
        }
        if let since, !MessageReader.isTimestamp(since) {
            throw ValidationError("--since must be a Slack message timestamp.")
        }
        if let maxMessages, !(1...2000).contains(maxMessages) {
            throw ValidationError("--max-messages must be between 1 and 2000.")
        }
        if let maxPages, maxPages <= 0 { throw ValidationError("--max-pages must be greater than zero.") }
    }

    func run() throws {
        try CommandSupport.run("read", options: options) { app, tree, deadline in
            let destination: Destination
            let route: NavigationResult.Route
            let config = target.hasDestination ? try Config.load() : nil
            if let requested = try target.resolve(using: config) {
                destination = requested
                route = try target.navigate(to: destination, app: app, in: tree, deadline: deadline).route
            } else {
                let client = try SlackWindow.currentWindow(in: tree)
                guard let current = client.location.destination else { throw RemoteError.slackNotReady }
                destination = current
                route = .alreadyThere
            }

            let view = try SlackWindow.verify(destination, in: tree)
            if target.hasDestination {
                _ = try Account.verify(team: destination.team, in: tree, config: config, access: .read,
                                       deadline: deadline, window: view.window, warn: app.warn)
            }
            if history {
                // Paging moves Slack's scroll position even when navigation was unnecessary.
                try Environment.requireSlackIdle(interrupt: target.interrupt)
                let snapshot = try History.read(destination, in: tree, since: since,
                    bounds: PageBounds(maxItems: maxMessages ?? 200, maxPages: maxPages ?? 50, deadline: deadline),
                    allowPartial: allowPartial)
                return Result(team: destination.team.rawValue, conversation: destination.conversation.rawValue,
                              route: route, scope: "history", complete: snapshot.complete,
                              stopReason: snapshot.stopReason, pages: snapshot.pages,
                              oldestTs: snapshot.messages.first?.ts, newestTs: snapshot.messages.last?.ts,
                              scrollRestored: snapshot.scrollRestored, readAt: Date().ISO8601Format(),
                              skippedItems: snapshot.skippedItems, messages: snapshot.messages)
            }
            let webArea = try view.window.one(Locators.webArea)
            guard Date() < deadline else { throw RemoteError.timeout }
            let (messages, skippedItems) = try MessageReader.read(view, limit: limit)

            // Check the live URL of the web area we read, then verify a fresh window tree.
            let location = webArea.string(.url).map(ClientLocation.parse) ?? .notClient
            guard location.destination == destination else {
                throw RemoteError.destinationMismatch(expected: destination, actual: location)
            }
            try tree.refresh()
            if !target.hasDestination {
                let current = try SlackWindow.currentWindow(in: tree)
                guard current.location.destination == destination else {
                    throw RemoteError.destinationMismatch(expected: destination, actual: current.location)
                }
            }
            _ = try SlackWindow.verify(destination, in: tree)
            guard Date() < deadline else { throw RemoteError.timeout }

            return Result(team: destination.team.rawValue, conversation: destination.conversation.rawValue,
                          route: route, readAt: Date().ISO8601Format(), skippedItems: skippedItems, messages: messages)
        }
    }
}
