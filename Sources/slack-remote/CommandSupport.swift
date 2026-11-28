import ArgumentParser
import Foundation
import SlackRemoteCore

struct CommandOptions: ParsableArguments {
    @Option(help: "Time limit for the command in seconds.") var timeout: Double = 15

    func validate() throws {
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
    private struct Success<Output: Encodable>: Encodable {
        var ok = true
        let command: String
        let slackVersion: String?
        let warnings: [String]
        let result: Output
    }

    private struct Failure<Output: Encodable>: Encodable {
        struct ErrorBody: Encodable {
            let code: String
            let message: String
            let details: [String: RemoteError.Detail]?
        }

        var ok = false
        let command: String
        let slackVersion: String?
        let warnings: [String]?
        let result: Output?
        let error: ErrorBody
    }

    /// Runs a local command and writes its JSON envelope to the appropriate stream.
    static func run<Output: Encodable>(_ command: String, work: () throws -> Output) throws {
        do {
            let envelope = Success(command: command, slackVersion: nil, warnings: [], result: try work())
            try write(envelope, to: .standardOutput)
        } catch {
            let failure = error as? RemoteError ?? .internalError(operation: "run_command")
            try writeFailure(command, error: failure, result: nil as Bool?)
            throw ExitCode(failure.exitStatus)
        }
    }

    static func writeFailure<Output: Encodable>(_ command: String, error: RemoteError, result: Output?) throws {
        let envelope = Failure(command: command, slackVersion: nil, warnings: nil, result: result,
                               error: .init(code: error.code, message: error.message, details: error.details))
        try write(envelope, to: .standardError)
    }

    private static func write(_ value: some Encodable, to handle: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0a)
        try handle.write(contentsOf: data)
    }
}
