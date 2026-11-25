import ArgumentParser
import Foundation
import SlackRemoteCore

enum RouteOption: String, ExpressibleByArgument {
    case auto, sidebar

    var preference: Navigator.RoutePreference { self == .sidebar ? .sidebar : .auto }
}

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

    @Option(help: "Configured destination name.") var dest: String?
    @Option(help: "Navigation route (auto or sidebar).") var route: RouteOption = .auto
    @Flag(help: "Allow changes while Slack is in use.") var interrupt = false

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
        if (requireDestination || user != nil || route != .auto), !hasDestination {
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

    func navigate(to destination: Destination, app: SlackApp, in tree: SlackTree, deadline: Date) throws
        -> NavigationResult {
        try Navigator(slackApp: app).navigate(to: destination, user: user, interrupt: interrupt,
                                              preference: route.preference, in: tree, deadline: deadline)
    }
}

enum Previewable<Actual: Encodable>: Encodable {
    case actual(Actual)
    case preview(DryRun)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .actual(let result): try result.encode(to: encoder)
        case .preview(let result): try result.encode(to: encoder)
        }
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
        _ command: String, options: CommandOptions, allowOverlays: Bool = false,
        output: ((SlackApp, Output) throws -> Void)? = nil,
        work: (SlackApp, SlackTree, Date) throws -> Output
    ) throws {
        var app: SlackApp?
        do {
            let (slack, result) = try withSession(options: options, allowOverlays: allowOverlays, prepare: {}) {
                slack, tree, deadline, _ in
                app = slack
                return try work(slack, tree, deadline)
            }
            if let output { try output(slack, result) }
            else { try succeed(command, app: slack, result: result) }
        } catch {
            try fail(command, error: remoteError(error), app: app, result: nil as Bool?)
        }
    }

    static func withSession<Context, Output>(
        options: CommandOptions, allowOverlays: Bool = false, prepare: () throws -> Context,
        work: (SlackApp, SlackTree, Date, Context) throws -> Output
    ) throws -> (SlackApp, Output) {
        let deadline = Date().addingTimeInterval(options.timeout)
        try CommandLock.acquire(deadline: deadline)
        let context = try prepare()
        try Environment.requireUnlocked(Environment.guiSession())
        try Environment.requireAccessibilityTrust()
        let running = try SlackApp.requireRunning()
        try SlackApp.requireVisible(running)
        let app = try SlackApp(running: running)
        let result = try app.withTree(deadline: deadline) { tree in
            if options.debug { debugTree(tree) }
            if !allowOverlays { try Overlays.requireUnblocked(in: tree) }
            return try work(app, tree, deadline, context)
        }
        return (app, result)
    }

    static func runLocal<Output: Encodable>(_ command: String, options: CommandOptions,
                                            work: () throws -> Output) throws {
        do {
            try CommandLock.acquire(deadline: Date().addingTimeInterval(options.timeout))
            try succeed(command, app: nil, result: work())
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
