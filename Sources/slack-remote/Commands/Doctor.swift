import ArgumentParser
import SlackRemoteCore

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check SlackRemote.app and its Slack sessions.")

    @OptionGroup var options: CommandOptions

    func run() throws {
        throw ExitCode(HelperClient.call(command: "doctor", operation: .doctor(DoctorRequest()), timeout: options.timeout))
    }
}
