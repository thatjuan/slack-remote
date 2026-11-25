import ArgumentParser
import Foundation
import SlackRemoteCore

struct Draft: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set or clear a verified conversation's draft.",
                                                    subcommands: [Set.self, Clear.self])

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Write text to an empty composer.")

        @OptionGroup var options: CommandOptions
        @OptionGroup var target: DestinationOptions
        @Option(help: "Text to put in the composer.") var text: String

        private struct Result: Encodable {
            let team: String
            let conversation: String
            let route: NavigationResult.Route
            let method: WriteMethod
            let length: Int
        }

        func validate() throws { _ = try target.requireDestination() }

        func run() throws {
            try WriteCommand.run("draft set", text: text, options: options, target: target) { view, tree, route, deadline in
                let composer = Composer(view: view, in: tree, requireIdle: WriteCommand.idleCheck(target))
                let method = try composer.write(text, deadline: deadline)
                return Result(team: view.destination.team.rawValue, conversation: view.destination.conversation.rawValue,
                              route: route, method: method, length: text.count)
            }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear a draft that matches the supplied text.")

        @OptionGroup var options: CommandOptions
        @OptionGroup var target: DestinationOptions
        @Option(help: "Exact text of the draft to clear.") var expectText: String

        private struct Result: Encodable {
            let team: String
            let conversation: String
            let route: NavigationResult.Route
            let cleared: Bool
        }

        func validate() throws { _ = try target.requireDestination() }

        func run() throws {
            try WriteCommand.run("draft clear", text: expectText, options: options, target: target) { view, tree, route, deadline in
                let composer = Composer(view: view, in: tree, requireIdle: WriteCommand.idleCheck(target))
                let cleared = try composer.clear(expecting: expectText, deadline: deadline)
                return Result(team: view.destination.team.rawValue, conversation: view.destination.conversation.rawValue,
                              route: route, cleared: cleared)
            }
        }
    }
}

enum WriteCommand {
    private struct Envelope<Output: Encodable>: Encodable {
        struct ErrorBody: Encodable {
            let code: String
            let message: String
            let details: [String: RemoteError.Detail]?
        }

        let ok: Bool
        let command: String
        let slackVersion: String?
        let warnings: [String]?
        let result: Output?
        let error: ErrorBody?
    }

    static func idleCheck(_ target: DestinationOptions) -> () throws -> Void {
        { try Environment.requireSlackIdle(interrupt: target.interrupt) }
    }

    static func run<Output: Encodable>(
        _ command: String, text: String, allowBroadcast: Bool = false, options: CommandOptions,
        target: DestinationOptions,
        work: (VerifiedView, SlackTree, NavigationResult.Route, Date) throws -> Output
    ) throws {
        let destination = try target.requireDestination()
        let deadline = Date().addingTimeInterval(options.timeout)
        var slackVersion: String?
        var warnings: [String]?
        var completedWork: Swift.Result<Output, any Error>?
        let outcome: Swift.Result<Output, any Error>
        do {
            try MessageText.validate(text, allowBroadcast: allowBroadcast)
            try Environment.requireUnlocked(Environment.guiSession())
            try Environment.requireAccessibilityTrust()
            let running = try SlackApp.requireRunning()
            try SlackApp.requireVisible(running)
            let slack = try SlackApp(running: running)
            slackVersion = slack.version
            warnings = slack.warnings
            try CommandLock.acquire(deadline: deadline)
            outcome = try slack.withTree(deadline: deadline) { tree in
                let result = Swift.Result {
                    if options.debug { CommandSupport.debugTree(tree) }
                    try idleCheck(target)()
                    let navigation = try Navigator(slackApp: slack).navigate(to: destination, user: target.user,
                        interrupt: target.interrupt, in: tree, deadline: deadline)
                    let view = try SlackWindow.verify(destination, in: tree)
                    return try work(view, tree, navigation.route, deadline)
                }
                completedWork = result
                return result
            }
        } catch {
            if let completedWork {
                // Preserve the verified send outcome if restoring the AX tree fails afterward.
                warnings?.append("tree_restore_failed")
                outcome = completedWork
            } else {
                outcome = .failure(error)
            }
        }

        let envelope: Envelope<Output>
        let status: Int32
        switch outcome {
        case .success(let result):
            envelope = .init(ok: true, command: command, slackVersion: slackVersion,
                             warnings: warnings, result: result, error: nil)
            status = 0
        case .failure(let error):
            let failure = error as? WriteFailure
            let remote = failure?.error ?? CommandSupport.remoteError(error)
            let details = failure.map(\.details) ?? remote.details
            envelope = .init(ok: false, command: command, slackVersion: slackVersion,
                             warnings: warnings, result: nil,
                             error: .init(code: remote.code, message: remote.message, details: details))
            status = remote.exitStatus
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(envelope)
        data.append(0x0a)
        let stream = status == 0 ? FileHandle.standardOutput : .standardError
        try stream.write(contentsOf: data)
        if status != 0 { throw ExitCode(status) }
    }
}
