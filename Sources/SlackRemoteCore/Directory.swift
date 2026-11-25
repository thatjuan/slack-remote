import AppKit
import Foundation

public enum Directory {
    private enum View: String {
        case channels, people

        var shortcut: String { self == .channels ? "L" : "E" }
        var list: Locator { self == .channels ? Locators.directoryChannels : Locators.directoryPeople }
    }

    public static func channels(team: TeamID, app: SlackApp, in tree: SlackTree,
                                bounds: PageBounds) throws -> Paged<SidebarList.Channel> {
        try withView(.channels, team: team, app: app, in: tree, deadline: bounds.deadline) {
            func rendered() throws -> [(key: ConversationID, node: any UINode, item: SidebarList.Channel)] {
                let list = try currentList(.channels, team: team, in: tree)
                let rows = list.children.filter(Locators.directoryChannelRow.matches)
                return try identifiedRows(rows) { row in
                    row.domID.flatMap(ConversationID.init(rawValue:))
                }.map { id, row in
                    let item = SidebarList.Channel(conversation: id, name: label(in: row), kind: .channel,
                                                   selected: false, hasDraft: false)
                    return (id, row, item)
                }
            }
            return try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: rendered,
                                                reachedBoundary: { _ in false }, atEnd: { false })
        }
    }

    public static func people(team: TeamID, app: SlackApp, in tree: SlackTree,
                              bounds: PageBounds) throws -> MemberList.Snapshot {
        try withView(.people, team: team, app: app, in: tree, deadline: bounds.deadline) {
            func rendered() throws -> [(key: UserID, node: any UINode, item: MemberList.Member)] {
                let grid = try currentList(.people, team: team, in: tree)
                // AXTable exposes each cell through its row and through its column.
                let rows = grid.children.filter(Locators.directoryPeopleRow.matches)
                let cells = rows.flatMap { $0.children.filter(Locators.directoryPersonCell.matches) }
                return try peopleRows(cells)
            }
            let listing = try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: rendered,
                                                       reachedBoundary: { _ in false }, atEnd: { false })
            return MemberList.Snapshot(listing: listing, expectedCount: nil)
        }
    }

    static func peopleRows(_ cells: [any UINode]) throws -> [(key: UserID, node: any UINode, item: MemberList.Member)] {
        let info = try identifiedRows(cells) { cell -> UserID? in
            guard let card = try? cell.one(Locators.directoryPersonInfo), let raw = card.domID,
                  raw.hasPrefix(Locators.directoryPersonIDPrefix) else { return nil }
            return UserID(String(raw.dropFirst(Locators.directoryPersonIDPrefix.count)))
        }
        return try info.map { user, node in
            let card = try node.one(Locators.directoryPersonInfo)
            return (user, node, MemberList.Member(user: user, label: label(in: card)))
        }
    }

    private static func label(in row: any UINode) -> String {
        let strong = row.descendants().first { $0.subrole == "AXStrongStyleGroup" }
        let text = strong?.all(Locators.directoryText).first ?? row.all(Locators.directoryText).first
        return text?.string(.value) ?? text?.string(.title) ?? ""
    }

    private static func withView<T>(_ view: View, team: TeamID, app: SlackApp, in tree: SlackTree,
                                    deadline: Date, _ body: () throws -> T) throws -> T {
        try restoringConversation(app: app, in: tree) {
            try Environment.requireSlackIdle(interrupt: false)
            guard Date() < deadline else { throw RemoteError.timeout }
            let startingLocation = try SlackWindow.currentWindow(in: tree).location
            try? NativeMenu(slackApp: app).press(cmdChar: view.shortcut, modifiers: 1)
            let nativeDeadline = min(deadline, Date().addingTimeInterval(1.5))
            let openedNatively = try Poll.until(nativeDeadline) {
                try directoryClient(team: team, in: tree).map { _ in true }
            }
            if openedNatively == nil {
                try tree.refresh()
                guard try SlackWindow.currentWindow(in: tree).location == startingLocation else {
                    throw RemoteError.uiDrift(locator: view.list.name, found: 0)
                }
                try openFromSidebar(in: tree, deadline: deadline)
            }
            let tab = try Poll.until(deadline) { () -> (any UINode)? in
                guard let client = try directoryClient(team: team, in: tree) else { return nil }
                return try exactTab(view, in: client.window)
            }
            guard let tab else { throw RemoteError.timeout }
            if !tab.domClasses.contains(Locators.activeTabClass) { try tab.perform(.press) }
            let ready = try Poll.until(deadline) { () -> Bool? in
                guard let client = try directoryClient(team: team, in: tree),
                      try exactTab(view, in: client.window).domClasses.contains(Locators.activeTabClass),
                      !client.window.all(view.list).isEmpty else { return nil }
                return true
            }
            guard ready == true else { throw RemoteError.timeout }
            return try body()
        }
    }

    private static func openFromSidebar(in tree: SlackTree, deadline: Date) throws {
        try Overlays.withModal(in: tree, deadline: deadline, opening: {
            let client = try SlackWindow.currentWindow(in: tree)
            let sidebar = try client.window.one(Locators.sidebarList)
            let rows = sidebar.all(Locators.sidebarRow).filter { $0.domID == Locators.sidebarEndID }
            guard rows.count == 1, let row = rows.first else {
                throw RemoteError.uiDrift(locator: Locators.sidebarEndID, found: rows.count)
            }
            try row.one(Locators.addChannelsButton).perform(.press)
        }) { modal in
            // Slack gives both items in this web menu generated IDs and the same classes.
            let choices = modal.all(Locators.addChannelsMenuItem).filter {
                $0.string(.title)?.localizedCaseInsensitiveCompare("Browse channels") == .orderedSame
            }
            guard choices.count == 1, let choice = choices.first else {
                throw RemoteError.uiDrift(locator: Locators.addChannelsMenuItem.name, found: choices.count)
            }
            try choice.perform(.press)
        }
    }

    private static func directoryClient(team: TeamID, in tree: SlackTree) throws -> ClientWindow? {
        try tree.refresh()
        let client = try SlackWindow.currentWindow(in: tree)
        guard case .other(let actual, _) = client.location, actual == team,
              client.window.all(Locators.directoryTabPanel).count == 1 else { return nil }
        try Overlays.requireUnblocked(in: tree)
        return client
    }

    private static func currentList(_ view: View, team: TeamID, in tree: SlackTree) throws -> any UINode {
        guard let client = try directoryClient(team: team, in: tree),
              try exactTab(view, in: client.window).domClasses.contains(Locators.activeTabClass) else {
            throw RemoteError.uiDrift(locator: view.list.name, found: 0)
        }
        return try client.window.one(view.list)
    }

    private static func exactTab(_ view: View, in window: any UINode) throws -> any UINode {
        let tabs = window.all(Locators.directoryTab).filter { $0.domID == view.rawValue }
        guard tabs.count == 1, let tab = tabs.first else {
            throw RemoteError.uiDrift(locator: Locators.directoryTab.name, found: tabs.count)
        }
        return tab
    }

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
        let restored = try SlackWindow.currentWindow(in: tree)
        guard restored.location.destination == destination else {
            throw RemoteError.destinationMismatch(expected: destination, actual: restored.location)
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

    private static func identifiedRows<ID>(_ rows: [any UINode], id: (any UINode) -> ID?) throws -> [(ID, any UINode)] {
        try rows.map { row in
            guard let id = id(row) else { throw RemoteError.unsupportedDestination }
            return (id, row)
        }
    }
}
