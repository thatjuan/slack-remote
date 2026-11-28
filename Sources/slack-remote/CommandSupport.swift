import ArgumentParser
import Foundation
import SlackRemoteCore

struct CommandOptions: ParsableArguments {
    @Option(help: "Time limit for the command in seconds.") var timeout: Double = 15

    func validate() throws {
        try Self.validateTimeout(timeout)
    }

    static func validateTimeout(_ timeout: Double) throws {
        guard timeout.isFinite, timeout > 0 else {
            throw ValidationError("--timeout must be a finite number greater than zero.")
        }
    }
}

struct DestinationOptions: ParsableArguments {
    @Option(help: "Slack workspace ID.", transform: { raw in
        guard let team = TeamID(raw) else { throw ValidationError("Expected a Slack team ID.") }
        return team
    }) var team: TeamID?

    @Option(help: "Slack channel, direct message or group ID.", transform: { raw in
        guard let conversation = ConversationID(raw) else { throw ValidationError("Expected a Slack conversation ID.") }
        return conversation
    }) var channel: ConversationID?

    @Option(help: "Configured destination name.") var dest: String?

    var hasDestination: Bool { dest != nil || team != nil }

    func validate() throws { try validate(requireDestination: false) }

    func validate(requireDestination: Bool) throws {
        if let dest {
            guard Config.isValidName(dest) else { throw ValidationError("Invalid destination name.") }
            guard team == nil, channel == nil else {
                throw ValidationError("--dest cannot be combined with --team or --channel.")
            }
        }
        guard (team == nil) == (channel == nil) else {
            throw ValidationError("Supply --team and --channel together.")
        }
        if requireDestination, !hasDestination {
            throw ValidationError("Supply --dest or both --team and --channel.")
        }
    }

    func resolve(using config: Config?) throws -> Destination? {
        if let dest {
            guard let destination = config?.destinations[dest] else { throw RemoteError.unsupportedDestination }
            return destination
        }
        if let team, let channel { return Destination(team: team, conversation: channel) }
        return nil
    }

    func requireDestination(using config: Config?) throws -> Destination {
        guard let destination = try resolve(using: config) else { throw RemoteError.unsupportedDestination }
        return destination
    }
}

enum CommandSupport {
    /// Runs a local command and writes its JSON envelope to the appropriate stream.
    static func run<Output: Encodable>(_ command: String, work: () throws -> Output) throws {
        do {
            try FileHandle.standardOutput.write(contentsOf: Envelope.success(command, result: try work()))
        } catch {
            let failure = error as? RemoteError ?? .internalError(operation: "run_command")
            try Envelope.writeFailure(command, error: failure)
            throw ExitCode(failure.exitStatus)
        }
    }
}
