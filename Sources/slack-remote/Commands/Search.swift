import ArgumentParser
import Foundation
import SlackRemoteCore

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run a query in Slack and read its rendered results.")

    @OptionGroup var options: CommandOptions
    @Option(help: "Query text, including any Slack search modifiers.") var query: String
    @Option(help: "Slack result tab to read.") var type = "messages"
    @Option(name: .customLong("in"), help: "Configured conversation name for the In filter.") var inName: String?
    @Option(help: "Workspace ID of the conversation for the In filter.", transform: { try Search.teamID($0) })
    var inTeam: TeamID?
    @Option(help: "Conversation ID for the In filter.", transform: { raw in
        guard let id = ConversationID(raw) else { throw ValidationError("Expected a Slack conversation ID.") }
        return id
    }) var inChannel: ConversationID?
    @Flag(help: "Filter to the signed-in sender.") var fromMe = false
    @Flag(help: "Filter to messages containing links.") var hasLink = false
    @Flag(help: "Filter to threads.") var threadsOnly = false
    @Option(help: "Maximum results to collect, up to 1,000.") var maxResults = 50
    @Option(help: "Maximum pages to collect.") var maxPages = 20
    @Flag(help: "Return available results if search paging stalls or reaches its deadline.") var allowPartial = false
    @Option(help: "Open the message result at this zero-based index.") var open: Int?
    @Option(help: "Workspace ID to search.", transform: { try Search.teamID($0) }) var team: TeamID?
    @Flag(help: "Allow UI changes while Slack is in use.") var interrupt = false

    private struct Output: Encodable {
        let team: TeamID
        let query: String
        let type: String
        let filters: SearchModal.Filters
        let availableTypes: [String]
        let sort: String?
        let complete: Bool
        let stopReason: StopReason
        let pages: Int
        let returnedTo: ConversationID?
        let results: [SearchResults.Hit]
        let opened: SearchResults.Opened?

        private enum CodingKeys: String, CodingKey {
            case team, query, type, filters, availableTypes, sort, complete, stopReason, pages, returnedTo, results, opened
        }

        func encode(to encoder: Encoder) throws {
            var value = encoder.container(keyedBy: CodingKeys.self)
            try value.encode(team, forKey: .team)
            try value.encode(query, forKey: .query)
            try value.encode(type, forKey: .type)
            try value.encode(filters, forKey: .filters)
            try value.encode(availableTypes, forKey: .availableTypes)
            try value.encode(sort, forKey: .sort)
            try value.encode(complete, forKey: .complete)
            try value.encode(stopReason, forKey: .stopReason)
            try value.encode(pages, forKey: .pages)
            try value.encodeIfPresent(returnedTo, forKey: .returnedTo)
            try value.encode(results, forKey: .results)
            try value.encodeIfPresent(opened, forKey: .opened)
        }
    }

    func validate() throws {
        do {
            try SearchModal.validate(query)
        } catch {
            throw ValidationError("--query must be nonempty and contain no control characters.")
        }
        if let inName {
            guard Config.isValidName(inName) else { throw ValidationError("Invalid destination name.") }
            guard inTeam == nil, inChannel == nil else {
                throw ValidationError("Use --in or both --in-team and --in-channel.")
            }
        }
        guard (inTeam == nil) == (inChannel == nil) else {
            throw ValidationError("Supply --in-team and --in-channel together.")
        }
        if let team, let inTeam, team != inTeam {
            throw ValidationError("--team and --in-team must match.")
        }
        guard !type.isEmpty else { throw ValidationError("--type must be a Slack result tab ID.") }
        guard (1...1000).contains(maxResults) else {
            throw ValidationError("--max-results must be between 1 and 1000.")
        }
        guard maxPages > 0 else { throw ValidationError("--max-pages must be greater than zero.") }
        if let open, open < 0 { throw ValidationError("--open must be zero or greater.") }
    }

    func run() throws {
        var runningApp: SlackApp?
        var sessionTree: SlackTree?
        do {
            let (app, output) = try CommandSupport.withSession(options: options, prepare: { try Config.load() }) {
                app, tree, deadline, config in
                runningApp = app
                sessionTree = tree
                return try search(using: app, tree: tree, deadline: deadline, config: config)
            }
            try CommandSupport.succeed("search", app: app, result: output)
        } catch {
            if sessionTree?.interruptionRequested == true {
                if let failure = error as? RemoteError {
                    try? CommandSupport.fail("search", error: failure, app: runningApp, result: nil as Bool?)
                }
                throw ExitCode(130)
            }
            if let unavailable = error as? SearchResults.UnsupportedType {
                try rejectType(unavailable, app: runningApp)
            }
            try CommandSupport.fail("search", error: CommandSupport.remoteError(error), app: runningApp,
                                    result: nil as Bool?)
        }
    }

    private func search(using app: SlackApp, tree: SlackTree, deadline: Date, config: Config?) throws -> Output {
        let client = try SlackWindow.currentWindow(in: tree)
        guard let start = client.location.destination else { throw RemoteError.slackNotReady }
        _ = try SlackWindow.verify(start, in: tree)
        try SearchResults.requireNoOpenResults(in: tree)
        let requested = try conversationFilter(using: config)
        let searchTeam = team ?? requested?.team ?? start.team
        if let requested, requested.team != searchTeam { throw RemoteError.unsupportedDestination }
        try SearchResults.requireSupportedConversation(requested?.conversation, for: type)
        let account = config?.accounts.first { $0.team == searchTeam }
        let anchor: Destination
        if let requested {
            anchor = requested
        } else if start.team == searchTeam {
            anchor = start
        } else if let selfDM = account?.selfDM {
            anchor = Destination(team: searchTeam, conversation: selfDM)
        } else {
            throw RemoteError.unsupportedDestination
        }
        _ = try Account.verify(team: searchTeam, in: tree, config: config, access: .read,
                               deadline: deadline, warn: app.warn)
        try Environment.requireSlackIdle(interrupt: interrupt)
        let navigator = Navigator(slackApp: app)
        let filters = SearchModal.Filters(conversation: requested?.conversation, fromMe: fromMe,
                                         hasLink: hasLink, threadsOnly: threadsOnly)

        return try SearchResults.restoring(start: start, in: tree, navigator: navigator,
                                           keepOnSuccess: open != nil) {
            if anchor != start {
                _ = try navigator.navigate(to: anchor, user: nil, interrupt: interrupt, in: tree, deadline: deadline)
                if searchTeam != start.team {
                    _ = try Account.verify(team: searchTeam, in: tree, config: config, access: .read,
                                           deadline: deadline, warn: app.warn)
                }
            }
            let snapshot = try SearchModal.run(query: query, filters: filters, from: anchor, account: account,
                                                in: tree, deadline: deadline, onOpen: {
                if options.debug { CommandSupport.debug("Search modal opened") }
            }) {
                try SearchResults.read(type: type, team: searchTeam, conversation: requested?.conversation, in: tree,
                                       bounds: PageBounds(maxItems: maxResults, maxPages: maxPages, deadline: deadline),
                                       allowPartial: allowPartial)
            }
            let opened = try open.map { try SearchResults.open($0, from: snapshot, team: searchTeam,
                                                               in: tree, deadline: deadline) }
            return Output(team: searchTeam, query: query, type: snapshot.type, filters: filters,
                          availableTypes: snapshot.availableTypes, sort: snapshot.sort, complete: snapshot.complete,
                          stopReason: snapshot.stopReason, pages: snapshot.pages,
                          returnedTo: opened == nil ? start.conversation : nil, results: snapshot.results, opened: opened)
        }
    }

    private func conversationFilter(using config: Config?) throws -> Destination? {
        if let inName {
            guard let destination = config?.destinations[inName] else { throw RemoteError.unsupportedDestination }
            return destination
        }
        if let inTeam, let inChannel { return Destination(team: inTeam, conversation: inChannel) }
        return nil
    }

    private static func teamID(_ raw: String) throws -> TeamID {
        guard let id = TeamID(raw) else { throw ValidationError("Expected a Slack team ID.") }
        return id
    }

    private func rejectType(_ failure: SearchResults.UnsupportedType, app: SlackApp?) throws -> Never {
        struct Failure: Encodable {
            struct Body: Encodable {
                let code = RemoteError.unsupportedDestination.code
                let message: String
                let details: [String: [String]]
            }
            let ok = false
            let command = "search"
            let slackVersion: String?
            let warnings: [String]?
            let error: Body
        }
        let message = failure.requiresUnscopedSearch
            ? "Slack did not show a verifiable conversation filter for the requested source."
            : "Slack did not show the requested result type."
        let envelope = Failure(slackVersion: app?.version, warnings: app?.warnings,
                               error: .init(message: message, details: ["availableTypes": failure.available]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileHandle.standardError.write(contentsOf: encoder.encode(envelope) + Data([0x0a]))
        throw ExitCode(RemoteError.unsupportedDestination.exitStatus)
    }
}
