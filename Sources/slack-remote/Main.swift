import ArgumentParser
import Darwin

@main
enum Entry {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "webkit-poc" {
            exit(HelperClient.forward(arguments: arguments))
        }
        SlackRemote.main()
    }
}

struct SlackRemote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slack-remote",
        abstract: "Read and write Slack through the signed-in sessions in SlackRemote.app.",
        version: SlackRemoteVersion.current,
        subcommands: [Dest.self]
    )
}
