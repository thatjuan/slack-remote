import ArgumentParser
import Foundation
import SlackRemoteCore

struct ListingOptions: ParsableArguments {
    @Option(help: "Maximum items to collect, up to 5,000.") var maxItems = 500
    @Option(help: "Maximum snapshots to collect.") var maxPages = 100
    @Flag(help: "Return available items if paging stalls or reaches its deadline.") var allowPartial = false

    func validate() throws {
        guard (1...5000).contains(maxItems) else {
            throw ValidationError("--max-items must be between 1 and 5000.")
        }
        guard maxPages > 0 else { throw ValidationError("--max-pages must be greater than zero.") }
    }

    func run<Output: Encodable>(_ command: String, options: CommandOptions,
                                work: (SlackApp, SlackTree, PageBounds) throws -> (Output, StopReason)) throws {
        var sessionApp: SlackApp?
        let app: SlackApp
        let result: Output
        let reason: StopReason
        do {
            (app, (result, reason)) = try CommandSupport.withSession(options: options, prepare: {}) {
                slack, tree, deadline, _ in
                sessionApp = slack
                return try work(slack, tree, PageBounds(maxItems: maxItems, maxPages: maxPages, deadline: deadline))
            }
        } catch {
            try CommandSupport.fail(command, error: CommandSupport.remoteError(error), app: sessionApp,
                                    result: nil as Output?)
        }
        if !allowPartial && (reason == .stalled || reason == .deadline) {
            try CommandSupport.fail(command, error: .partialResult, app: app, result: result)
        }
        try CommandSupport.succeed(command, app: app, result: result)
    }
}

struct ListingWorkspace: ParsableArguments {
    @Option(help: "Slack workspace ID.", transform: { raw in
        guard let team = TeamID(raw) else { throw ValidationError("Expected a Slack team ID.") }
        return team
    }) var team: TeamID?
}

struct Channels: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List Slack sidebar or channel browser conversations.")

    enum Source: String, ExpressibleByArgument, Encodable { case sidebar, browser }

    @OptionGroup var options: CommandOptions
    @OptionGroup var listing: ListingOptions
    @OptionGroup var workspace: ListingWorkspace
    @Option(help: "Conversation source (sidebar or browser).") var source: Source = .sidebar

    private struct Result: Encodable {
        let team: TeamID
        let source: Source
        let complete: Bool
        let stopReason: StopReason
        let pages: Int
        let channels: [SidebarList.Channel]
    }

    func run() throws {
        try listing.run("channels", options: options) { app, tree, bounds in
            return try Directory.withWorkspace(workspace.team, app: app, in: tree, deadline: bounds.deadline) { team in
                _ = try Account.verify(team: team, in: tree, config: Config.load(), access: .read,
                                       deadline: bounds.deadline, warn: app.warn)
                try Environment.requireSlackIdle(interrupt: false)
                let snapshot: Paged<SidebarList.Channel>
                switch source {
                case .sidebar: snapshot = try SidebarList.read(team: team, in: tree, bounds: bounds)
                case .browser: snapshot = try Directory.channels(team: team, app: app, in: tree, bounds: bounds)
                }
                return (Result(team: team, source: source, complete: snapshot.complete,
                               stopReason: snapshot.stopReason, pages: snapshot.pages,
                               channels: snapshot.items), snapshot.stopReason)
            }
        }
    }
}
