import ArgumentParser
import Foundation
import SlackRemoteCore

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read the messages Slack has rendered.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Keep this many of the newest rendered messages.") var limit: Int?

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        let scope = "rendered"
        let skippedItems: Int
        let messages: [Message]
    }

    func validate() throws {
        if let limit, limit < 0 {
            throw ValidationError("--limit must be zero or greater.")
        }
    }

    func run() throws {
        try CommandSupport.run("read", options: options) { app, tree, deadline in
            let destination: Destination
            let route: NavigationResult.Route
            if let requested = target.destination {
                destination = requested
                route = try Navigator(slackApp: app).navigate(to: destination, user: target.user,
                    interrupt: target.interrupt, in: tree, deadline: deadline).route
            } else {
                let client = try SlackWindow.currentWindow(in: tree)
                guard let current = client.location.destination else { throw RemoteError.slackNotReady }
                destination = current
                route = .alreadyThere
            }

            let view = try SlackWindow.verify(destination, in: tree)
            let webArea = try view.window.one(Locators.webArea)
            guard Date() < deadline else { throw RemoteError.timeout }
            let (messages, skippedItems) = try MessageReader.read(view, limit: limit)

            // Check the live URL of the web area we read, then verify a fresh window tree.
            let location = webArea.string(.url).map(ClientLocation.parse) ?? .notClient
            guard location.destination == destination else {
                throw RemoteError.destinationMismatch(expected: destination, actual: location)
            }
            tree.refresh()
            if target.destination == nil {
                let current = try SlackWindow.currentWindow(in: tree)
                guard current.location.destination == destination else {
                    throw RemoteError.destinationMismatch(expected: destination, actual: current.location)
                }
            }
            _ = try SlackWindow.verify(destination, in: tree)
            guard Date() < deadline else { throw RemoteError.timeout }

            return Result(team: destination.team.rawValue, conversation: destination.conversation.rawValue,
                          route: route, skippedItems: skippedItems, messages: messages)
        }
    }
}
