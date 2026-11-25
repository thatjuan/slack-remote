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
            try readChannels(team: team, in: tree, bounds: bounds)
        }
    }

    static func readChannels(team: TeamID, in tree: SlackTree, bounds: PageBounds) throws -> Paged<SidebarList.Channel> {
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

    static func openFromSidebar(in tree: SlackTree, deadline: Date) throws {
        try tree.refresh()
        try Overlays.requireUnblocked(in: tree)
        var ownedPopup: (any UINode)?
        let result = Result {
            let client = try SlackWindow.currentWindow(in: tree)
            let sidebar = try client.window.one(Locators.sidebarList)
            let rows = sidebar.all(Locators.sidebarRow).filter { $0.domID == Locators.sidebarEndID }
            guard rows.count == 1, let row = rows.first else {
                throw RemoteError.uiDrift(locator: Locators.sidebarEndID, found: rows.count)
            }
            guard Date() < deadline else { throw RemoteError.timeout }
            try row.one(Locators.addChannelsButton).perform(.press)
            guard let popup = try Poll.until(deadline, {
                try tree.refresh()
                let client = try SlackWindow.currentWindow(in: tree)
                let matches = client.window.descendants().filter { node in
                    Overlays.kind(node) == .modal
                        && node.all(Locators.addChannelsMenuItem).contains(where: Locators.isBrowseChannels)
                }
                guard matches.count <= 1 else {
                    throw RemoteError.uiDrift(locator: Locators.addChannelsMenuItem.name, found: matches.count)
                }
                guard !matches.isEmpty else { return nil as (any UINode)? }
                guard Overlays.open(in: tree) == [.modal] else { throw RemoteError.uiBlocked }
                return matches.first
            }) else { throw RemoteError.timeout }
            ownedPopup = popup
            let choices = popup.all(Locators.addChannelsMenuItem).filter(Locators.isBrowseChannels)
            guard choices.count == 1, let choice = choices.first else {
                throw RemoteError.uiDrift(locator: Locators.addChannelsMenuItem.name, found: choices.count)
            }
            try choice.perform(.press)
        }
        // Selecting Browse replaces the conversation with the directory. Cleanup
        // only waits for the owned menu to close; withView verifies the new view.
        try tree.withCleanup {
            try tree.refresh()
            guard !Overlays.open(in: tree).isEmpty else { return }
            if case .success = result {
                let dismissed: Bool? = try Poll.until(tree.cleanupDeadline(after: 0.5)) {
                    try tree.refresh()
                    return Overlays.open(in: tree).isEmpty ? true : nil
                }
                if dismissed == true { return }
            }
            guard let ownedPopup else { throw RemoteError.overlayLeftOpen }
            let window = try SlackWindow.currentWindow(in: tree).window
            let backdrops = window.all(Locators.modalOverlay).filter { backdrop in
                backdrop.descendants().contains { popup in
                    guard Overlays.kind(popup) == .modal else { return false }
                    if let original = ownedPopup as? AXNode, let refreshed = popup as? AXNode {
                        return original.referencesSameElement(as: refreshed)
                    }
                    return ownedPopup as AnyObject === popup as AnyObject
                }
            }
            guard backdrops.count == 1, let backdrop = backdrops.first else { throw RemoteError.overlayLeftOpen }
            try? backdrop.perform(.press)
            guard try Poll.until(tree.cleanupDeadline(after: 2), {
                try tree.refresh()
                return Overlays.open(in: tree).isEmpty ? true : nil
            }) == true else { throw RemoteError.overlayLeftOpen }
        }
        try result.get()
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
        try restoringConversation(in: tree, navigator: Navigator(slackApp: app), body)
    }

    static func restoringConversation<T>(in tree: SlackTree, navigator: Navigator,
                                         _ body: () throws -> T) throws -> T {
        try tree.refresh()
        let start = try SlackWindow.currentWindow(in: tree)
        guard let destination = start.location.destination else { throw RemoteError.unsupportedDestination }
        _ = try SlackWindow.verify(destination, in: tree)
        let result = Result { try body() }
        try tree.refresh()
        guard Overlays.open(in: tree).isEmpty else { throw RemoteError.overlayLeftOpen }
        let current = try SlackWindow.currentWindow(in: tree)
        if current.location != start.location {
            _ = try navigator.navigate(to: destination, user: nil, interrupt: true,
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
