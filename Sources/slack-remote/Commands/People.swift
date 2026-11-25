import ArgumentParser
import SlackRemoteCore

struct People: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the Slack workspace people directory.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var listing: ListingOptions
    @OptionGroup var workspace: ListingWorkspace

    func run() throws {
        try listing.run("people", options: options) { app, tree, bounds in
            try Directory.withWorkspace(workspace.team, app: app, in: tree, deadline: bounds.deadline) { team in
                _ = try Account.verify(team: team, in: tree, config: Config.load(), access: .read,
                                       deadline: bounds.deadline, warn: app.warn)
                let snapshot = try Directory.people(team: team, app: app, in: tree, bounds: bounds)
                return (MemberListingResult(team: team, snapshot: snapshot), snapshot.listing.stopReason)
            }
        }
    }
}
