import ArgumentParser
import Foundation
import SlackRemoteCore

struct CommandOptions: ParsableArguments {
    @Option(help: "Time limit for the command in seconds.") var timeout: Double = 15
    @Flag(help: "Print aggregate Accessibility diagnostics to stderr.") var debug = false

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

    @Option(help: "Slack user ID for a direct message link.", transform: { raw in
        guard let user = UserID(raw) else { throw ValidationError("Expected a Slack user ID.") }
        return user
    }) var user: UserID?

    @Flag(help: "Allow changes while Slack is in use.") var interrupt = false

    func validate() throws {
        guard (team == nil) == (channel == nil) else {
            throw ValidationError("Supply --team and --channel together.")
        }
        if user != nil, team == nil {
            throw ValidationError("--user requires --team and --channel.")
        }
    }

    var destination: Destination? {
        guard let team, let channel else { return nil }
        return Destination(team: team, conversation: channel)
    }

    func requireDestination() throws -> Destination {
        guard let destination else { throw ValidationError("--team and --channel are required.") }
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

    static func run<Output: Encodable>(
        _ command: String, options: CommandOptions,
        work: (SlackApp, SlackTree, Date) throws -> Output
    ) throws {
        let deadline = Date().addingTimeInterval(options.timeout)
        do {
            try Environment.requireUnlocked(Environment.guiSession())
            try Environment.requireAccessibilityTrust()
            let running = try SlackApp.requireRunning()
            try SlackApp.requireVisible(running)
            let app = try SlackApp(running: running)
            try CommandLock.acquire(deadline: deadline)
            let result = try app.withTree(deadline: deadline) { tree in
                if options.debug { debugTree(tree) }
                return try work(app, tree, deadline)
            }
            try succeed(command, app: app, result: result)
        } catch {
            try fail(command, error: remoteError(error), result: nil as Bool?)
        }
    }

    static func succeed<Output: Encodable>(_ command: String, app: SlackApp?, result: Output) throws {
        let envelope = Success(command: command, slackVersion: app?.version,
                               warnings: app?.warnings ?? [], result: result)
        try write(envelope, to: .standardOutput)
    }

    static func fail<Output: Encodable>(_ command: String, error: RemoteError,
                                         app: SlackApp? = nil, result: Output?) throws -> Never {
        let envelope = Failure(command: command, slackVersion: app?.version, warnings: app?.warnings, result: result,
                               error: .init(code: error.code, message: error.message, details: error.details))
        try write(envelope, to: .standardError)
        throw ExitCode(error.exitStatus)
    }

    static func remoteError(_ error: any Error) -> RemoteError {
        error as? RemoteError ?? .internalError(operation: "run_command")
    }

    static func treeDetail(_ tree: SlackTree) -> String? {
        guard let info = tree.sessionInfo else { return nil }
        let seconds = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), info.elapsed)
        return "\(info.mode.rawValue), settled in \(seconds) s, \(info.nodeCount) nodes"
    }

    static func debugTree(_ tree: SlackTree) {
        let counts = [Locators.webArea, Locators.primaryView].map { locator in
            let count = tree.windows.reduce(0) { $0 + $1.all(locator).count }
            return "\(locator.name)=\(count)"
        }.joined(separator: " ")
        debug([treeDetail(tree), counts].compactMap { $0 }.joined(separator: " | "))
    }

    static func debug(_ detail: String) {
        try? FileHandle.standardError.write(contentsOf: Data("\(detail)\n".utf8))
    }

    private static func write(_ value: some Encodable, to handle: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0a)
        try handle.write(contentsOf: data)
    }
}
