import ArgumentParser
import Darwin

@main
enum Entry {
    static func main() {
        if let status = HelperClient.forwardIfAvailable(arguments: Array(CommandLine.arguments.dropFirst())) {
            exit(status)
        }
        SlackRemote.main()
    }
}

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
