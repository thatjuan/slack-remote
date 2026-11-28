import ArgumentParser
import SlackRemoteCore

extension ChannelsRequest.Source: ExpressibleByArgument {}

/// Lists conversations for the selected workspace.
struct Channels: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List Slack conversations or the public channel directory.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var workspace: WorkspaceOptions
    @OptionGroup var listing: ListingOptions
    @Option(help: "List member conversations or all public channels.") var source: ChannelsRequest.Source = .member
    @Flag(help: "Include archived channels.") var includeArchived = false

    func run() throws {
        let request = ChannelsRequest(team: workspace.team, source: source, includeArchived: includeArchived,
                                      limit: listing.limit, allowPartial: listing.allowPartial)
        throw ExitCode(HelperClient.call(command: "channels", operation: .channels(request), timeout: options.timeout))
    }
}
