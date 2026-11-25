import ArgumentParser
import SlackRemoteCore

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open and verify a Slack conversation.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        let focusRestored: Bool
    }

    func validate() throws {
        _ = try target.requireDestination()
    }

    func run() throws {
        let destination = try target.requireDestination()
        try CommandSupport.run("open", options: options) { app, tree, deadline in
            let navigation = try Navigator(slackApp: app).navigate(to: destination, user: target.user,
                interrupt: target.interrupt, in: tree, deadline: deadline)
            return Result(team: destination.team.rawValue, conversation: destination.conversation.rawValue,
                          route: navigation.route, focusRestored: navigation.focusRestored)
        }
    }
}
