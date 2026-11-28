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
            return try Self.resolveNamed(dest, using: config)
        }
        if let team, let channel { return Destination(team: team, conversation: channel) }
        return nil
    }

    static func resolveNamed(_ name: String, using config: Config?) throws -> Destination {
        guard let destination = config?.destinations[name] else { throw RemoteError.unsupportedDestination }
        return destination
    }

    func requireDestination(using config: Config?) throws -> Destination {
        guard let destination = try resolve(using: config) else { throw RemoteError.unsupportedDestination }
        return destination
    }
}

struct ListingOptions: ParsableArguments {
    @Option(help: "Maximum rows to return, from 1 to 5,000.") var limit = 500
    @Flag(help: "Return the rows collected before the deadline.") var allowPartial = false

    func validate() throws {
        try CommandSupport.validateLimit(limit, maximum: 5000)
    }
}

struct WorkspaceOptions: ParsableArguments {
    @Option(help: "Slack workspace ID.", transform: { raw in
        guard let team = TeamID(raw) else { throw ValidationError("Expected a Slack team ID.") }
        return team
    }) var team: TeamID?
}

enum CommandSupport {
    static func validateLimit(_ limit: Int, maximum: Int) throws {
        guard (1...maximum).contains(limit) else {
            throw ValidationError("--limit must be between 1 and \(maximum).")
        }
    }

    /// Resolves config-backed options before sending the typed operation to the helper.
    static func call(_ command: String, timeout: Double, operation: () throws -> SlackRemoteCore.Operation) throws {
        let request: SlackRemoteCore.Operation
        do {
            request = try operation()
        } catch let error as RemoteError {
            try Envelope.writeFailure(command, error: error)
            throw ExitCode(error.exitStatus)
        }
        throw ExitCode(HelperClient.call(command: command, operation: request, timeout: timeout))
    }

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
