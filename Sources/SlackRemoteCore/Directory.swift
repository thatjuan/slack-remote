import AppKit
import Foundation

public enum Directory {
    public static func withWorkspace<T>(_ requested: TeamID?, app: SlackApp, in tree: SlackTree, deadline: Date,
                                        _ body: (TeamID) throws -> T) throws -> T {
        guard let requested else {
            let current = try SlackWindow.currentWindow(in: tree)
            guard let team = current.location.team else { throw RemoteError.slackNotReady }
            return try body(team)
        }
        return try restoringConversation(app: app, in: tree) {
            try Environment.requireSlackIdle(interrupt: false)
            try openWorkspace(requested, app: app, in: tree, deadline: deadline)
            return try body(requested)
        }
    }

    /// Preserve the starting conversation when an operation opens a different view.
    public static func restoringConversation<T>(app: SlackApp, in tree: SlackTree,
                                                 _ body: () throws -> T) throws -> T {
        try tree.refresh()
        let start = try SlackWindow.currentWindow(in: tree)
        guard let destination = start.location.destination else { throw RemoteError.unsupportedDestination }
        _ = try SlackWindow.verify(destination, in: tree)
        let result = Result { try body() }
        try tree.refresh()
        let current = try SlackWindow.currentWindow(in: tree)
        if current.location != start.location {
            _ = try Navigator(slackApp: app).navigate(to: destination, user: nil, interrupt: true,
                                                      in: tree, deadline: Date().addingTimeInterval(5))
        }
        _ = try SlackWindow.verify(destination, in: tree)
        return try result.get()
    }

    private static func openWorkspace(_ team: TeamID, app: SlackApp, in tree: SlackTree, deadline: Date) throws {
        guard Date() < deadline else { throw RemoteError.timeout }
        let bundle = try app.bundleURLForNavigation()
        let url = URL(string: "slack://open?team=\(team.rawValue)")!
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: bundle, configuration: configuration, completionHandler: nil)
        let ready: Bool? = try Poll.until(deadline) {
            try tree.refresh()
            try Overlays.requireUnblocked(in: tree)
            let current = try SlackWindow.currentWindow(in: tree)
            return current.location.team == team ? true : nil
        }
        guard ready == true else { throw RemoteError.timeout }
    }

    static func identifiedRows<ID>(_ rows: [any UINode], id: (any UINode) -> ID?) throws -> [(ID, any UINode)] {
        try rows.map { row in
            guard let id = id(row) else { throw RemoteError.unsupportedDestination }
            return (id, row)
        }
    }
}
