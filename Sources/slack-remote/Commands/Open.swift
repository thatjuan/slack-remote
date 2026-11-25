import ArgumentParser
import SlackRemoteCore

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open and verify a Slack conversation.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Flag(help: "Show the plan without changing Slack.") var dryRun = false

    private struct Result: Encodable {
        let team: String
        let conversation: String
        let route: NavigationResult.Route
        let focusRestored: Bool
    }

    func validate() throws {
        try target.validate(requireDestination: true)
    }

    func run() throws {
        try CommandSupport.run("open", options: options) { app, tree, deadline in
            let config = try Config.load()
            let destination = try target.requireDestination(using: config)
            let output: Previewable<Result>
            if dryRun {
                output = .preview(try DryRun.preview(.open, destination: destination, user: target.user,
                                                    preference: target.route.preference, config: config,
                                                    in: tree, deadline: deadline, warn: app.warn))
            } else {
                let navigation = try target.navigate(to: destination, app: app, in: tree, deadline: deadline)
                let view = try SlackWindow.verify(destination, in: tree)
                _ = try Account.verify(team: destination.team, in: tree, config: config, access: .read,
                                       deadline: deadline, window: view.window, warn: app.warn)
                output = .actual(Result(team: destination.team.rawValue, conversation: destination.conversation.rawValue,
                                        route: navigation.route, focusRestored: navigation.focusRestored))
            }
            return output
        }
    }
}
