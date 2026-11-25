import AppKit
import Foundation

public struct NavigationResult: Encodable {
    public enum Route: String, Encodable {
        case alreadyThere = "already_there"
        case deepLinkChannel = "deep_link_channel"
        case deepLinkUser = "deep_link_user"
        case sidebarRow = "sidebar_row"
    }

    public let route: Route
    public let focusRestored: Bool
}

public struct Navigator {
    public enum RoutePreference: String, CaseIterable { case auto, sidebar }

    private struct FrontmostApp {
        let bundleID: String?
        let restore: () -> Bool
    }

    private let openLink: (URL) throws -> Void
    private let frontmost: () -> FrontmostApp?
    private let secondsSinceUserInput: () -> Double

    public init(openLink: @escaping (URL) throws -> Void,
                frontmostBundleID: @escaping () -> String?,
                activate: @escaping (_ bundleID: String) -> Void,
                secondsSinceUserInput: @escaping () -> Double) {
        self.openLink = openLink
        self.frontmost = {
            guard let bundleID = frontmostBundleID() else { return nil }
            return FrontmostApp(bundleID: bundleID) {
                activate(bundleID)
                return true
            }
        }
        self.secondsSinceUserInput = secondsSinceUserInput
    }

    public init(slackApp: SlackApp) {
        openLink = { url in
            let bundleURL = try slackApp.bundleURLForNavigation()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.promptsUserIfNeeded = false
            configuration.addsToRecentItems = false
            NSWorkspace.shared.open([url], withApplicationAt: bundleURL, configuration: configuration,
                                    completionHandler: nil)
        }
        frontmost = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let identity = ProcessIdentity(app)
            return FrontmostApp(bundleID: app.bundleIdentifier) {
                guard let current = identity?.currentApplication(), current == app else { return false }
                return current.activate(options: [])
            }
        }
        secondsSinceUserInput = Environment.secondsSinceUserInput
    }

    public static func plannedRoute(to destination: Destination, user: UserID?,
                                    preference: RoutePreference = .auto) -> NavigationResult.Route {
        if preference == .sidebar { return .sidebarRow }
        if destination.conversation.kind == .directMessage && user != nil { return .deepLinkUser }
        return .deepLinkChannel
    }

    public func navigate(to destination: Destination, user: UserID?, interrupt: Bool,
                         preference: RoutePreference = .auto, forReading: Bool = false,
                         in tree: SlackTree, deadline: Date) throws -> NavigationResult {
        func requireUnblocked() throws {
            if forReading { try Overlays.requireUnblockedForConversationRead(in: tree) }
            else { try Overlays.requireUnblocked(in: tree) }
        }

        guard Date() < deadline else { throw RemoteError.timeout }
        try tree.refresh()
        try requireUnblocked()
        var lastLocation: ClientLocation
        do {
            _ = try SlackWindow.verifyDestination(destination, in: tree)
            guard Date() < deadline else { throw RemoteError.timeout }
            if preference == .auto { return NavigationResult(route: .alreadyThere, focusRestored: false) }
            lastLocation = .conversation(destination, trailing: [])
        } catch let error as RemoteError {
            guard case .destinationMismatch(_, let actual) = error, actual.destination != destination else {
                throw error
            }
            lastLocation = actual
        }

        let previousFrontmost = frontmost()
        try Environment.requireSlackIdle(interrupt: interrupt, frontmostBundleID: previousFrontmost?.bundleID,
                                         secondsSinceUserInput: secondsSinceUserInput)
        guard Date() < deadline else { throw RemoteError.timeout }

        func restoreFocus() -> Bool {
            guard let previousFrontmost, previousFrontmost.bundleID != SlackApp.bundleIdentifier,
                  frontmost()?.bundleID == SlackApp.bundleIdentifier else { return false }
            return previousFrontmost.restore()
        }

        var focusHandled = false
        defer { if !focusHandled { _ = restoreFocus() } }
        let route = Self.plannedRoute(to: destination, user: user, preference: preference)
        switch route {
        case .deepLinkChannel, .alreadyThere:
            try openLink(destination.channelLink)
        case .deepLinkUser:
            guard let user else { throw RemoteError.internalError(operation: "plan_user_link") }
            try openLink(destination.userLink(user))
        case .sidebarRow:
            try pressSidebarRow(for: destination, in: tree, deadline: deadline)
        }

        var previousShape: [Int]?
        let settled: Bool? = try Poll.until(deadline) {
            try tree.refresh()
            do { try requireUnblocked() }
            catch { throw RemoteError.overlayLeftOpen }
            do {
                _ = try SlackWindow.verifyDestination(destination, in: tree)
                lastLocation = .conversation(destination, trailing: [])
                let shape = tree.shape()
                defer { previousShape = shape }
                return shape != nil && shape == previousShape ? true : nil
            } catch {
                lastLocation = SlackWindow.observedLocation(in: SlackWindow.clientWindows(in: tree))
                previousShape = nil
                return nil
            }
        }
        let focusRestored = restoreFocus()
        focusHandled = true
        guard settled == true else { throw RemoteError.destinationMismatch(expected: destination, actual: lastLocation) }
        return NavigationResult(route: route, focusRestored: focusRestored)
    }

    private func pressSidebarRow(for destination: Destination, in tree: SlackTree, deadline: Date) throws {
        let client = try SlackWindow.currentWindow(in: tree)
        let control = try Self.requireSidebarTarget(for: destination, in: client)
        guard Date() < deadline else { throw RemoteError.timeout }
        try control.perform(.press)
    }

    @discardableResult
    static func requireSidebarTarget(for destination: Destination, in client: ClientWindow) throws -> any UINode {
        _ = try client.window.one(Locators.webArea)
        guard client.location.team == destination.team else {
            throw RemoteError.destinationMismatch(expected: destination, actual: client.location)
        }
        let rows = client.window.all(Locators.sidebarRow).filter { $0.domID == destination.conversation.rawValue }
        guard let row = rows.first else { throw RemoteError.destinationUnreachable }
        guard rows.count == 1 else { throw RemoteError.uiDrift(locator: Locators.sidebarRow.name, found: rows.count) }

        // Slack exposes the row and its conversation control as separate AXPress targets.
        return try row.one(Locators.sidebarRowTarget)
    }
}
