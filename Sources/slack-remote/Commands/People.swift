import ArgumentParser
import SlackRemoteCore

/// Lists the users in a workspace.
struct People: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List people in a Slack workspace.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var workspace: WorkspaceOptions
    @OptionGroup var listing: ListingOptions
    @Flag(help: "Include bots and Slackbot.") var includeBots = false
    @Flag(help: "Include deleted users.") var includeDeleted = false

    func run() throws {
        let request = PeopleRequest(team: workspace.team, includeBots: includeBots, includeDeleted: includeDeleted,
                                    limit: listing.limit, allowPartial: listing.allowPartial)
        throw ExitCode(HelperClient.call(command: "people", operation: .people(request), timeout: options.timeout))
    }
}
