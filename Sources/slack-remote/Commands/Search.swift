import ArgumentParser
import Foundation
import SlackRemoteCore

extension SearchRequest.Kind: ExpressibleByArgument {}
extension SearchRequest.Sort: ExpressibleByArgument {}

/// Parses a Slack search and resolves any configured conversation name.
struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Search a Slack workspace for messages or files.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var workspace: WorkspaceOptions
    @Option(help: "Slack search query.") var query: String
    @Option(help: "Search messages or files.") var type: SearchRequest.Kind = .messages
    @Option(name: .customLong("in"), help: "Search a configured destination.") var destinationName: String?
    @Option(help: "Search a Slack conversation ID.", transform: { raw in
        guard let channel = ConversationID(raw) else { throw ValidationError("Expected a Slack conversation ID.") }
        return channel
    }) var inChannel: ConversationID?
    @Flag(help: "Search items from the signed-in user.") var fromMe = false
    @Flag(help: "Search messages containing a link.") var hasLink = false
    @Flag(help: "Search within threads.") var threadsOnly = false
    @Option(help: "Sort by score or timestamp.") var sort: SearchRequest.Sort = .score
    @Option(help: "Maximum matches to return, from 1 to 1,000.") var limit = 50
    @Flag(help: "Return the matches collected before the deadline.") var allowPartial = false

    func validate() throws {
        try CommandSupport.validateLimit(limit, maximum: 1000)
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("--query must contain text.")
        }
        if let destinationName {
            guard Config.isValidName(destinationName) else { throw ValidationError("Invalid destination name.") }
            guard inChannel == nil else { throw ValidationError("--in and --in-channel are mutually exclusive.") }
        }
    }

    func run() throws {
        try CommandSupport.call("search", timeout: options.timeout) {
            var team = workspace.team
            var channel = inChannel
            if let destinationName {
                let destination = try DestinationOptions.resolveNamed(destinationName, using: Config.load())
                guard team == nil || team == destination.team else { throw RemoteError.unsupportedDestination }
                team = destination.team
                channel = destination.conversation
            }
            return .search(.init(query: query, type: type, team: team, channel: channel, fromMe: fromMe,
                                 hasLink: hasLink, threadsOnly: threadsOnly, sort: sort, limit: limit,
                                 allowPartial: allowPartial))
        }
    }
}
