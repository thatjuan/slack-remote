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
    // These failures carry an observation alongside the foundation error code and details.
    private struct Failure: Encodable {
        struct ErrorBody: Encodable {
            let code: String
            let message: String
            let details: [String: RemoteError.Detail]?
        }

        var ok = false
        let command: String
        let slackVersion: String?
        let warnings: [String]?
        let error: ErrorBody
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
        var app: SlackApp?
        do {
            try MessageText.validate(text, allowBroadcast: allowBroadcast)
            try Environment.requireUnlocked(Environment.guiSession())
            try Environment.requireAccessibilityTrust()
            let running = try SlackApp.requireRunning()
            try SlackApp.requireVisible(running)
            let slack = try SlackApp(running: running)
            app = slack
            try CommandLock.acquire(deadline: deadline)
            let result = try slack.withTree(deadline: deadline) { tree in
                if options.debug { CommandSupport.debugTree(tree) }
                try idleCheck(target)()
                let navigation = try Navigator(slackApp: slack).navigate(to: destination, user: target.user,
                    interrupt: target.interrupt, in: tree, deadline: deadline)
                let view = try SlackWindow.verify(destination, in: tree)
                return try work(view, tree, navigation.route, deadline)
            }
            try CommandSupport.succeed(command, app: slack, result: result)
        } catch let failure as WriteFailure {
            let envelope = Failure(command: command, slackVersion: app?.version, warnings: app?.warnings,
                error: .init(code: failure.error.code, message: failure.error.message, details: failure.details))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(envelope)
            data.append(0x0a)
            try FileHandle.standardError.write(contentsOf: data)
            throw ExitCode(failure.error.exitStatus)
        } catch {
            try CommandSupport.fail(command, error: CommandSupport.remoteError(error), app: app, result: nil as Bool?)
        }
    }
}
