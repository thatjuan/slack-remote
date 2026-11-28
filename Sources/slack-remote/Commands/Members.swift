import ArgumentParser
import SlackRemoteCore

/// Lists the users in a conversation.
struct Members: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the members of a Slack conversation.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @OptionGroup var listing: ListingOptions

    func validate() throws {
        try target.validate(requireDestination: true)
    }

    func run() throws {
        try CommandSupport.call("members", timeout: options.timeout) {
            let destination = try target.requireDestination(using: Config.load())
            return .members(.init(destination: destination, limit: listing.limit, allowPartial: listing.allowPartial))
        }
    }
}
