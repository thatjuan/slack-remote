import ArgumentParser
import SlackRemoteCore

struct Whoami: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Identify the signed-in user in a Slack workspace.")

    @OptionGroup var options: CommandOptions
    @Option(help: "Slack workspace ID.", transform: { raw in
        guard let team = TeamID(raw) else { throw ValidationError("Expected a Slack team ID.") }
        return team
    }) var team: TeamID?

    func run() throws {
        throw ExitCode(HelperClient.call(command: "whoami", operation: .whoami(WhoamiRequest(team: team)),
                                         timeout: options.timeout))
    }
}
