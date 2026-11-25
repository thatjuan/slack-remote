import ArgumentParser

@main
struct SlackRemote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slack-remote",
        abstract: "Control the Slack desktop client in the current macOS session.",
        version: SlackRemoteVersion.current,
        subcommands: [
            Doctor.self, Current.self, Open.self, Read.self, Draft.self, Send.self,
            Whoami.self, Dest.self, Inspect.self, Reply.self, React.self, Channels.self,
            Members.self, People.self, Search.self, Upload.self,
        ]
    )
}
