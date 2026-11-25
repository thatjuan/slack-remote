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
        @Flag(help: "Show the plan without changing Slack.") var dryRun = false

        private struct Result: Encodable {
            let team: String
            let conversation: String
            let route: NavigationResult.Route
            let method: WriteMethod
            let length: Int
        }

        func validate() throws { try target.validate(requireDestination: true) }

        func run() throws {
            try WriteCommand.run("draft set", text: text, options: options, target: target,
                                 preview: dryRun ? .draftSet(text) : nil) { view, tree, route, deadline in
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
        @Flag(help: "Show the plan without changing Slack.") var dryRun = false

        private struct Result: Encodable {
            let team: String
            let conversation: String
            let route: NavigationResult.Route
            let cleared: Bool
        }

        func validate() throws { try target.validate(requireDestination: true) }

        func run() throws {
            try WriteCommand.run("draft clear", text: expectText, checkEmojiNames: false, options: options, target: target,
                                 preview: dryRun ? .draftClear(expectText) : nil) { view, tree, route, deadline in
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
        _ command: String, text: String, allowBroadcast: Bool = false, checkEmojiNames: Bool = true,
        options: CommandOptions, target: DestinationOptions, preview: DryRun.Operation?,
        work: (VerifiedView, SlackTree, NavigationResult.Route, Date) throws -> Output
    ) throws {
        try run(command, options: options, target: target, preview: preview, validateInput: {
            try MessageText.validate(text, allowBroadcast: allowBroadcast, checkEmojiNames: checkEmojiNames)
        }, work: work)
    }

    static func run<Output: Encodable>(
        _ command: String, options: CommandOptions,
        target: DestinationOptions, preview: DryRun.Operation?,
        validateInput: () throws -> Void,
        work: (VerifiedView, SlackTree, NavigationResult.Route, Date) throws -> Output
    ) throws {
        try runUsingApp(command, options: options, target: target, preview: preview, validateInput: validateInput) {
            _, _, view, tree, route, deadline in
            try work(view, tree, route, deadline)
        }
    }

    static func runUsingApp<Output: Encodable>(
        _ command: String, options: CommandOptions,
        target: DestinationOptions, preview: DryRun.Operation?,
        validateInput: () throws -> Void,
        work: (SlackApp, Config?, VerifiedView, SlackTree, NavigationResult.Route, Date) throws -> Output
    ) throws {
        typealias Outcome = Swift.Result<Previewable<Output>, any Error>
        var app: SlackApp?
        var sessionTree: SlackTree?
        var completedWork: Outcome?
        let outcome: Outcome
        do {
            try validateInput()
            let (_, result) = try CommandSupport.withSession(options: options, prepare: {
                let config = try Config.load()
                let destination = try target.requireDestination(using: config)
                try config?.requireWriteAllowed(to: destination)
                return (config, destination)
            }) { slack, tree, deadline, prepared in
                app = slack
                sessionTree = tree
                let (config, destination) = prepared
                let result = Outcome {
                    if let preview {
                        return .preview(try DryRun.preview(preview, destination: destination, user: target.user,
                            preference: target.route.preference, config: config, in: tree, deadline: deadline,
                            warn: slack.warn))
                    }
                    try idleCheck(target)()
                    let navigation = try target.navigate(to: destination, app: slack, in: tree, deadline: deadline)
                    let view = try SlackWindow.verify(destination, in: tree)
                    _ = try Account.verify(team: destination.team, in: tree, config: config, access: .write,
                                           deadline: deadline, window: view.window, warn: slack.warn)
                    let verified = try SlackWindow.verify(destination, in: tree)
                    return .actual(try work(slack, config, verified, tree, navigation.route, deadline))
                }
                completedWork = result
                return result
            }
            outcome = result
        } catch {
            if let completedWork {
                // Preserve the verified send outcome if restoring the AX tree fails afterward.
                app?.warn("tree_restore_failed")
                outcome = completedWork
            } else {
                outcome = .failure(error)
            }
        }

        let envelope: Envelope<Previewable<Output>>
        let status: Int32
        switch outcome {
        case .success(let result):
            envelope = .init(ok: true, command: command, slackVersion: app?.version,
                             warnings: app?.warnings, result: result, error: nil)
            status = 0
        case .failure(let error):
            let failure = error as? WriteFailure
            let interrupted = sessionTree?.interruptionRequested == true
            let remote = failure?.error ?? (error as? RemoteError)
                ?? (interrupted ? .interrupted : CommandSupport.remoteError(error))
            let details = failure.map(\.details) ?? remote.details
            envelope = .init(ok: false, command: command, slackVersion: app?.version,
                             warnings: app?.warnings, result: nil,
                             error: .init(code: remote.code, message: remote.message, details: details))
            status = interrupted ? RemoteError.interrupted.exitStatus : remote.exitStatus
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
