import ArgumentParser
import SlackRemoteCore

struct Upload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Upload a file to a verified Slack conversation or thread.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var target: DestinationOptions
    @Option(help: "Path to the local file.") var file: String
    @Option(help: "Text to send with the file.") var text: String?
    @Option(help: "The parent message's Slack timestamp.") var thread: String?
    @Flag(help: "Share the thread reply with the conversation.") var alsoSendToChannel = false
    @Option(help: "Maximum file size in bytes, up to 1 GB.") var maxSize = FileStaging.defaultLimit
    @Flag(help: "Allow @channel, @here and @everyone mentions.") var allowBroadcast = false
    @Flag(help: "Show the plan without changing Slack.") var dryRun = false

    private struct Result: Encodable {
        let team: TeamID
        let conversation: ConversationID
        let thread: String?
        let file: FileStaging.File
        let route: NavigationResult.Route
        let attachMethod: Uploader.AttachMethod
        let ts: String

        private enum CodingKeys: String, CodingKey {
            case team, conversation, thread, file, route, attachMethod, sent, ts
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(team, forKey: .team)
            try values.encode(conversation, forKey: .conversation)
            try values.encode(thread, forKey: .thread)
            try values.encode(file, forKey: .file)
            try values.encode(route, forKey: .route)
            try values.encode(attachMethod, forKey: .attachMethod)
            try values.encode(true, forKey: .sent)
            try values.encode(ts, forKey: .ts)
        }
    }

    func validate() throws {
        try target.validate(requireDestination: true)
        if let thread, !MessageReader.isTimestamp(thread) {
            throw ValidationError("--thread must be a Slack message timestamp.")
        }
        if alsoSendToChannel, thread == nil {
            throw ValidationError("--also-send-to-channel requires --thread.")
        }
    }

    func run() throws {
        let source: FileStaging
        do {
            source = try FileStaging(path: file, maxSize: maxSize)
        } catch {
            try CommandSupport.fail("upload", error: CommandSupport.remoteError(error), result: nil as Bool?)
        }
        let idle = WriteCommand.idleCheck(target)
        let preview: DryRun.Operation? = dryRun
            ? .upload(file: source.file, text: text, thread: thread, broadcast: alsoSendToChannel)
            : nil
        try WriteCommand.runUsingApp("upload", options: options, target: target, primaryComposer: thread == nil,
                                     preview: preview, validateInput: {
            if let text { try MessageText.validate(text, allowBroadcast: allowBroadcast) }
        }) { app, config, view, tree, route, deadline in
            let account = { (window: any UINode) in
                let verification = try Account.verify(team: view.destination.team, in: tree, config: config,
                                                      access: .dryRunWrite, deadline: deadline, window: window)
                if verification == .unverified { throw RemoteError.accountUnverified }
            }
            try account(view.window)
            let scope: MessageScope
            if let thread {
                let pane = try ThreadView.open(view.destination, rootTs: thread, in: tree,
                                               deadline: deadline, requireIdle: idle)
                scope = .thread(pane)
            } else {
                scope = .primary
            }
            let uploader = Uploader(view: view, scope: scope, in: tree, requireIdle: idle, requireAccount: account)
            let receipt = try uploader.upload(source, text: text, alsoSendToChannel: alsoSendToChannel,
                                              deadline: deadline, paste: {
                try NativeMenu(slackApp: app).press(cmdChar: "V", modifiers: 0)
            })
            return Result(team: view.destination.team, conversation: view.destination.conversation, thread: thread,
                          file: source.file, route: route, attachMethod: receipt.attachMethod, ts: receipt.ts)
        }
    }
}
