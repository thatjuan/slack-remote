import ArgumentParser

@main
struct SlackRemote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slack-remote",
        abstract: "Read and write Slack through the signed-in sessions in SlackRemote.app.",
        version: SlackRemoteVersion.current,
        subcommands: [Doctor.self, Whoami.self, Accounts.self, Dest.self]
    )
}
