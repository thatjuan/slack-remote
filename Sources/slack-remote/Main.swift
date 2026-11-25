import ArgumentParser

@main
struct SlackRemote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slack-remote",
        abstract: "Control the Slack desktop client in the current macOS session.",
        subcommands: [Doctor.self, Current.self, Open.self]
    )
}
