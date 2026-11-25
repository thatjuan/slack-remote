import Foundation

public enum SearchResults {
    public struct UnsupportedType: Error {
        public let available: [String]
        public let requiresUnscopedSearch: Bool

        init(available: [String], requiresUnscopedSearch: Bool = false) {
            self.available = available
            self.requiresUnscopedSearch = requiresUnscopedSearch
        }
    }

    public struct Opened: Encodable, Equatable {
        public let team: TeamID
        public let conversation: ConversationID
        public let ts: String
        public let inThread: Bool
    }

    public struct Hit: Encodable {
        public let index: Int
        let content: Content

        public func encode(to encoder: Encoder) throws {
            var value = encoder.container(keyedBy: CodingKeys.self)
            try value.encode(index, forKey: .index)
            try value.encode(content.kind, forKey: .kind)
            try value.encode(content.hasID ? "dom_id" : "none", forKey: .idSource)
            switch content {
            case .message(let identity, let sender, let text):
                try value.encode(identity?.conversation, forKey: .conversation)
                try value.encode(identity?.ts, forKey: .ts)
                try value.encode(sender, forKey: .sender)
                try value.encode(text, forKey: .text)
            case .file(let file, let name, let conversation):
                try value.encode(file, forKey: .file)
                try value.encode(name, forKey: .name)
                try value.encode(conversation, forKey: .conversation)
            case .channel(let conversation, let name):
                try value.encode(conversation, forKey: .conversation)
                try value.encode(name, forKey: .name)
            case .person(let user, let label):
                try value.encode(user, forKey: .user)
                try value.encode(label, forKey: .label)
            case .other(let label):
                try value.encode(label, forKey: .label)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case index, kind, idSource, conversation, ts, sender, text, file, name, user, label
        }
    }

    public struct Snapshot {
        public let type: String
        public let availableTypes: [String]
        public let sort: String?
        let page: Paged<Row>

        public var pages: Int { page.pages }
        public var complete: Bool { page.complete }
        public var stopReason: StopReason { page.stopReason }
        public var results: [Hit] { page.items.enumerated().map { Hit(index: $0.offset, content: $0.element.content) } }
    }

    struct MessageIdentity: Hashable {
        let conversation: ConversationID
        let ts: String
    }

    enum Content: Hashable {
        case message(MessageIdentity?, sender: String?, text: String)
        case file(String?, name: String?, conversation: ConversationID?)
        case channel(ConversationID?, name: String?)
        case person(UserID?, label: String?)
        case other(label: String?)

        var kind: String {
            switch self {
            case .message: return "message"
            case .file: return "file"
            case .channel: return "channel"
            case .person: return "person"
            case .other: return "other"
            }
        }

        var hasID: Bool {
            switch self {
            case .message(let identity, _, _): return identity != nil
            case .file(let file, _, _): return file != nil
            case .channel(let conversation, _): return conversation != nil
            case .person(let user, _): return user != nil
            case .other: return false
            }
        }
    }

    enum RowKey: Hashable {
        case domID(String)
        case sameContent(Content, occurrence: Int)
    }

    struct Row {
        let key: RowKey
        let content: Content
    }

    private struct Tab {
        let type: String
        let control: any UINode
        var selected: Bool { control.domClasses.contains(Locators.searchTabSelected) }
    }

    private struct View {
        let root: any UINode
        let tabs: [Tab]
        let scope: Destination?

        var types: [String] { tabs.isEmpty ? ["messages"] : tabs.map(\.type) }
        func isSelected(_ type: String) -> Bool {
            tabs.isEmpty || tabs.filter(\.selected).map(\.type) == [type]
        }
    }

    /// Slack removes an explicit In filter when these workspace sources are selected.
    public static func requireSupportedConversation(_ conversation: ConversationID?, for type: String) throws {
        if conversation != nil, isWorkspaceSource(type) { throw RemoteError.unsupportedDestination }
    }

    public static func read(type: String, team: TeamID, conversation: ConversationID? = nil, in tree: SlackTree,
                            bounds: PageBounds, allowPartial: Bool, onReady: () -> Void = {}) throws -> Snapshot {
        guard var initial = try Poll.until(bounds.deadline, { try loaded(team: team, in: tree) }) else {
            throw RemoteError.timeout
        }
        if let scope = initial.scope {
            if let conversation, scope.conversation != conversation { throw mismatch(Destination(team: team, conversation: conversation), in: tree) }
            let launchers = initial.root.all(Locators.scopedSearchActions).flatMap { $0.all(Locators.scopedSearchExpand) }
            guard launchers.count <= 1 else { throw RemoteError.uiDrift(locator: Locators.scopedSearchExpand.name, found: launchers.count) }
            if let expand = launchers.first {
                guard Date() < bounds.deadline else { throw RemoteError.timeout }
                try tree.checkInterruption()
                try expand.perform(.press)
                guard let full = try Poll.until(bounds.deadline, {
                    guard let view = try loaded(team: team, in: tree), view.scope == nil else { return nil as View? }
                    return view
                }) else { throw RemoteError.timeout }
                initial = full
            }
        }
        let requiresConversationScope = conversation != nil || hasConversationFilter(in: initial.root)
        let available: [String]
        if initial.tabs.isEmpty, initial.scope == nil, !initial.root.all(Locators.searchSources).isEmpty {
            available = try selectSource(type, team: team, conversation: conversation, in: tree,
                                         requiresConversationScope: requiresConversationScope, deadline: bounds.deadline)
        } else {
            available = initial.types
        }
        guard available.contains(type) else {
            throw UnsupportedType(available: available)
        }
        try requireSupportedScope(for: type, available: available, conversation: conversation,
                                  requiresConversationScope: requiresConversationScope)
        if let tab = initial.tabs.first(where: { $0.type == type }), !tab.selected {
            guard tab.control.actionNames.contains(UIAction.press.rawValue), Date() < bounds.deadline else {
                throw RemoteError.uiDrift(locator: Locators.searchTab.name, found: 0)
            }
            try tree.checkInterruption()
            try tab.control.perform(.press)
        }
        guard let ready = try Poll.until(bounds.deadline, {
            guard let view = try loaded(team: team, in: tree), view.isSelected(type) else { return nil as View? }
            return view
        }) else { throw RemoteError.timeout }
        if requiresConversationScope, ready.scope == nil, !hasConversationFilter(in: ready.root) {
            throw UnsupportedType(available: available, requiresUnscopedSearch: true)
        }
        let sort = try readSort(in: ready, tree: tree, deadline: bounds.deadline)
        onReady()
        var atEnd = false
        let page = try VirtualListPager.collect(direction: .towardEnd, bounds: bounds, rendered: {
            guard let view = try current(team: team, in: tree), view.isSelected(type), view.scope == ready.scope else {
                throw RemoteError.uiDrift(locator: Locators.searchResults.name, found: 0)
            }
            let rows = try rendered(type: type, in: view)
            if let conversation {
                for row in rows {
                    if case .message(let identity?, _, _) = row.item.content, identity.conversation != conversation {
                        throw mismatch(Destination(team: team, conversation: conversation), in: tree)
                    }
                }
            }
            // The full page exposes a regular AX list. The channel pane virtualizes previews.
            atEnd = view.scope == nil || view.root.descendants().contains { $0.domID == Locators.scopedSearchEmptyID }
            return rows
        }, reachedBoundary: { _ in false }, atEnd: { atEnd })
        try page.requireAllowed(allowPartial: allowPartial)
        return Snapshot(type: type, availableTypes: available, sort: sort, page: page)
    }

    public static func open(_ index: Int, from snapshot: Snapshot, team: TeamID, in tree: SlackTree,
                            deadline: Date) throws -> Opened {
        guard snapshot.page.items.indices.contains(index),
              case .message(let identity?, _, _) = snapshot.page.items[index].content else {
            throw RemoteError.unsupportedDestination
        }
        let row = snapshot.page.items[index]
        let destination = Destination(team: team, conversation: identity.conversation)
        guard let view = try current(team: team, in: tree), view.isSelected(snapshot.type) else {
            throw mismatch(destination, in: tree)
        }
        let matches = try rendered(type: snapshot.type, in: view).filter { candidate in
            guard candidate.key == row.key, case .message(let actual?, _, _) = candidate.item.content else { return false }
            return actual == identity
        }
        guard matches.count == 1, let target = matches.first?.node, Date() < deadline else {
            throw mismatch(destination, in: tree)
        }

        try tree.checkInterruption()
        if target.actionNames.contains(UIAction.press.rawValue) {
            try target.perform(.press)
        } else if target.actionNames.contains(UIAction.showMenu.rawValue) {
            // Full search rows expose Jump in their semantic message action menu.
            try withMenu(in: tree, deadline: deadline, opening: { try target.perform(.showMenu) }) { menu in
                let jump = try menu.one(Locators.searchResultJump)
                guard Date() < deadline else { throw RemoteError.timeout }
                try tree.checkInterruption()
                try jump.perform(.press)
            }
        } else {
            throw mismatch(destination, in: tree)
        }
        func arrival() throws -> Opened? {
            try tree.refresh()
            let client = try SlackWindow.currentWindow(in: tree)
            guard client.location.destination == destination, Overlays.open(in: tree).isEmpty,
                  !isFullSearch(client.location) else { return nil }
            if let primary = try? client.window.one(Locators.primaryView),
               primary.all(Locators.messageItem).filter({ $0.domID == "message-list_\(identity.ts)" }).count == 1 {
                return Opened(team: team, conversation: identity.conversation, ts: identity.ts, inThread: false)
            }
            let threadItems = client.window.all(Locators.secondaryView).flatMap { $0.descendants() }.filter { node in
                guard let id = node.domID else { return false }
                let prefix = "\(identity.conversation.rawValue)-"
                let suffix = "-thread-list-Thread_\(identity.ts)"
                guard id.hasPrefix(prefix), id.hasSuffix(suffix), id.count > prefix.count + suffix.count else {
                    return false
                }
                return MessageReader.isTimestamp(String(id.dropFirst(prefix.count).dropLast(suffix.count)))
            }
            guard threadItems.count == 1 else { return nil }
            return Opened(team: team, conversation: identity.conversation, ts: identity.ts, inThread: true)
        }
        guard try Poll.until(deadline, arrival) != nil else { throw mismatch(destination, in: tree) }
        let cleanup = Date().addingTimeInterval(4)
        try clearActiveQuery(in: tree, deadline: cleanup)
        try dismissScoped(in: tree, deadline: cleanup)
        guard let opened = try arrival() else { throw mismatch(destination, in: tree) }
        return opened
    }

    public static func requireNoOpenResults(in tree: SlackTree) throws {
        let window = try SlackWindow.currentWindow(in: tree).window
        guard window.all(Locators.scopedSearchHeader).isEmpty else { throw RemoteError.uiBlocked }
    }

    /// Results, including partial results and errors, are held until the starting view is verified.
    public static func restoring<T>(start: Destination, in tree: SlackTree, navigator: Navigator,
                                    keepOnSuccess: Bool, _ work: () throws -> T) throws -> T {
        tree.unwindOnSignal = true
        let outcome = Result {
            try tree.checkInterruption()
            return try work()
        }
        if keepOnSuccess, !tree.interruptionRequested, case .success = outcome { return try outcome.get() }
        try tree.withCleanup {
            do {
                try tree.refresh()
                try Overlays.requireUnblockedForConversationRead(in: tree)
                let current = try SlackWindow.currentWindow(in: tree)
                if isFullSearch(current.location) || !current.window.all(Locators.scopedSearchHeader).isEmpty {
                    try clearActiveQuery(in: tree, deadline: tree.cleanupDeadline(after: 3))
                }
                try dismissScoped(in: tree, deadline: tree.cleanupDeadline(after: 4))
                if try SlackWindow.currentWindow(in: tree).location.destination != start {
                    _ = try navigator.navigate(to: start, user: nil, interrupt: true, forReading: true, in: tree,
                                               deadline: tree.cleanupDeadline(after: 4))
                }
                let view = try SlackWindow.verifyForReading(start, in: tree)
                guard view.window.all(Locators.scopedSearchHeader).isEmpty,
                      try SlackWindow.currentWindow(in: tree).location.destination == start else {
                    throw mismatch(start, in: tree)
                }
            } catch let error as RemoteError where error.code == "overlay_left_open" || error.code == "ui_blocked" {
                throw RemoteError.overlayLeftOpen
            } catch {
                throw mismatch(start, in: tree)
            }
        }
        let value = try outcome.get()
        try tree.checkInterruption()
        return value
    }

    private static func mismatch(_ expected: Destination, in tree: SlackTree) -> RemoteError {
        .destinationMismatch(expected: expected, actual: SlackWindow.observedLocation(in: SlackWindow.clientWindows(in: tree)))
    }

    private static func current(team: TeamID, in tree: SlackTree) throws -> View? {
        try tree.refresh()
        let client = try SlackWindow.currentWindow(in: tree)
        let matchedPanes = client.window.all(Locators.secondaryView).filter {
            !$0.all(Locators.scopedSearchHeader).isEmpty
        }
        if !matchedPanes.isEmpty {
            guard matchedPanes.count == 1, let pane = matchedPanes.first,
                  let destination = client.location.destination, destination.team == team else {
                throw RemoteError.uiDrift(locator: Locators.scopedSearchHeader.name, found: matchedPanes.count)
            }
            return View(root: pane, tabs: [], scope: destination)
        }
        guard isFullSearch(client.location) else { return nil }
        let roots = client.window.all(Locators.searchResults)
        guard !roots.isEmpty else { return nil }
        guard client.location.team == team, roots.count == 1, let root = roots.first else {
            throw RemoteError.uiDrift(locator: Locators.searchResults.name, found: roots.count)
        }
        let tabs = root.all(Locators.searchTab).compactMap { node -> Tab? in
            guard let id = node.domID, !id.isEmpty else { return nil }
            return Tab(type: id, control: node)
        }
        guard Set(tabs.map(\.type)).count == tabs.count else {
            throw RemoteError.uiDrift(locator: Locators.searchTab.name, found: tabs.count)
        }
        return View(root: root, tabs: tabs, scope: nil)
    }

    private static func isFullSearch(_ location: ClientLocation) -> Bool {
        if case .other(_, let path) = location { return path.first == "search" }
        return false
    }

    private static func hasConversationFilter(in root: any UINode) -> Bool {
        root.descendants().contains {
            $0.domID == "filter-in" && $0.domClasses.contains(Locators.searchFilterActive)
        }
    }

    private static func requireSupportedScope(for type: String, available: [String], conversation: ConversationID?,
                                              requiresConversationScope: Bool) throws {
        let channelDMSource = type == "dms" && conversation.map { $0.kind != .directMessage } == true
        if (requiresConversationScope && isWorkspaceSource(type)) || channelDMSource {
            throw UnsupportedType(available: available, requiresUnscopedSearch: true)
        }
    }

    private static func isWorkspaceSource(_ type: String) -> Bool {
        type == "people" || type == "channels"
    }

    private static func readSort(in view: View, tree: SlackTree, deadline: Date) throws -> String? {
        let controls = view.root.descendants().filter { $0.domID == Locators.searchResultSortID }
        guard controls.count == 1, let control = controls.first else { return nil }
        if let value = control.string(.value), !value.isEmpty { return value }
        guard control.actionNames.contains(UIAction.press.rawValue), Date() < deadline else { return nil }
        return try withMenu(in: tree, deadline: deadline, opening: { try control.perform(.press) },
                            fallback: { window in
            guard let root = try? window.one(Locators.searchResults) else { return nil }
            let matches = root.descendants().filter { $0.domID == Locators.searchResultSortID }
            return matches.count == 1 ? matches.first : nil
        }) { menu in
            let chosen = menu.all(Locators.searchSourceItem).filter { $0.domClasses.contains(Locators.searchSourceChecked) }
            guard chosen.count == 1,
                  let id = chosen.first?.domID?.wholeMatch(of: #/menu-[0-9]+-([0-9]+)/#) else { return nil }
            return ["0": "most_relevant", "1": "newest", "2": "oldest"][String(id.1)]
        }
    }

    private struct Source {
        let type: String
        let node: any UINode
        var checked: Bool { node.domClasses.contains(Locators.searchSourceChecked) }
    }

    private static func selectSource(_ type: String, team: TeamID, conversation: ConversationID?,
                                     in tree: SlackTree, requiresConversationScope: Bool,
                                     deadline: Date) throws -> [String] {
        let selection: (available: [String], changed: Bool) = try withSources(team: team, in: tree, deadline: deadline) { options in
            let available = options.map(\.type)
            guard let desired = options.first(where: { $0.type == type }) else { throw UnsupportedType(available: available) }
            try requireSupportedScope(for: type, available: available, conversation: conversation,
                                      requiresConversationScope: requiresConversationScope)
            guard Date() < deadline else { throw RemoteError.timeout }
            let changed = !desired.checked
            if changed {
                try tree.checkInterruption()
                try desired.node.perform(.press)
            }
            return (available, changed)
        }
        if selection.changed {
            try withSources(team: team, in: tree, deadline: deadline) { options in
                guard options.filter(\.checked).map(\.type) == [type] else {
                    throw RemoteError.uiDrift(locator: Locators.searchSources.name, found: 0)
                }
            }
        }
        return selection.available
    }

    private static func withSources<T>(team: TeamID, in tree: SlackTree, deadline: Date,
                                       _ work: ([Source]) throws -> T) throws -> T {
        try Overlays.requireUnblocked(in: tree)
        guard let view = try current(team: team, in: tree), view.scope == nil, Date() < deadline else {
            throw RemoteError.timeout
        }
        let button = try view.root.one(Locators.searchSources)
        return try withMenu(in: tree, deadline: deadline, opening: { try button.perform(.press) },
                            fallback: { window in
            try? window.one(Locators.searchResults).one(Locators.searchSources)
        }) { menu in
            let items = menu.all(Locators.searchSourceItem)
            let indexes = items.compactMap { $0.domID?.wholeMatch(of: #/menu-([0-9]+)-([0-9]+)/#) }
            // The Sources menu uses generated IDs. Its six rows preceding the
            // separator occupy fixed slots in the observed client.
            let types = ["messages", "dms", "files", "people", "channels", "canvases"]
            guard indexes.count == items.count,
                  Set(indexes.map { String($0.1) }).count == 1,
                  indexes.prefix(types.count).map({ Int($0.2) }) == types.indices.map(Optional.some) else {
                throw RemoteError.uiDrift(locator: Locators.searchSourceItem.name, found: items.count)
            }
            return try work(zip(types, items).map { Source(type: $0.0, node: $0.1) })
        }
    }

    private struct Menu {
        let node: any UINode
        let popup: any UINode
        let client: ClientWindow

        func matches(_ candidate: Menu) -> Bool {
            guard client.location == candidate.client.location,
                  SearchPopup(node: client.window).matches(candidate.client.window) else { return false }
            if SearchPopup(node: popup).matches(candidate.popup) { return true }
            // The popover can be absent from the backdrop's AX subtree. Its generated
            // item IDs identify the menu across Accessibility snapshots.
            let items = node.all(Locators.searchSourceItem)
            let ids = items.compactMap(\.domID)
            return !ids.isEmpty && ids.count == items.count
                && ids.allSatisfy { $0.wholeMatch(of: #/menu-[0-9]+-[0-9]+/#) != nil }
                && ids.map(Optional.some) == candidate.node.all(Locators.searchSourceItem).map(\.domID)
        }
    }

    private static func currentMenu(in tree: SlackTree) throws -> Menu? {
        try tree.refresh()
        let client = try SlackWindow.currentWindow(in: tree)
        let window = client.window
        let matches = window.all(Locators.searchSourceMenu)
        guard matches.count <= 1 else { throw RemoteError.uiDrift(locator: Locators.searchSourceMenu.name, found: matches.count) }
        guard let menu = matches.first else { return nil }
        let popups = window.descendants().filter {
            $0.domClasses.contains(Locators.modalContent) && $0.all(Locators.searchSourceMenu).count == 1
        }
        guard popups.count == 1, let popup = popups.first else { throw RemoteError.overlayLeftOpen }
        return Menu(node: menu, popup: popup, client: client)
    }

    private static func withMenu<T>(in tree: SlackTree, deadline: Date, opening: () throws -> Void,
                                    fallback: (any UINode) -> (any UINode)? = { _ in nil },
                                    _ work: (any UINode) throws -> T) throws -> T {
        try tree.refresh()
        try Overlays.requireUnblocked(in: tree)
        var owned: Menu?
        let outcome = Result {
            try tree.checkInterruption()
            try opening()
            guard let menu = try Poll.until(deadline, { try currentMenu(in: tree) }) else { throw RemoteError.timeout }
            owned = menu
            try tree.checkInterruption()
            return try work(menu.node)
        }
        try tree.withCleanup { try closeMenu(in: tree, owned: owned, fallback: fallback) }
        try tree.checkInterruption()
        return try outcome.get()
    }

    private static func closeMenu(in tree: SlackTree, owned: Menu?,
                                  fallback: (any UINode) -> (any UINode)?) throws {
        guard let visible = try currentMenu(in: tree) else { return }
        guard let owned else { throw RemoteError.overlayLeftOpen }
        let deadline = tree.cleanupDeadline(after: 6)

        func dismiss(_ visible: Menu) throws {
            guard owned.matches(visible) else { throw RemoteError.overlayLeftOpen }
            let window = visible.client.window
            let popup = SearchPopup(node: visible.popup)
            let backdrops = window.all(Locators.modalOverlay).filter { backdrop in
                backdrop.all(Locators.informationalTooltip).isEmpty
                    && backdrop.descendants().contains(where: popup.matches)
            }
            guard backdrops.count <= 1, let close = backdrops.first
                    ?? (Overlays.open(in: tree) == [.modal] ? fallback(window) : nil),
                  Date() < deadline else { throw RemoteError.overlayLeftOpen }
            try? close.perform(.press)
        }

        func dismissed(until limit: Date) throws -> Bool {
            try Poll.until(limit) {
                if let visible = try currentMenu(in: tree) {
                    guard owned.matches(visible) else { throw RemoteError.overlayLeftOpen }
                    return nil as Bool?
                }
                return Overlays.open(in: tree).isEmpty ? true : nil
            } == true
        }

        try dismiss(visible)
        if try dismissed(until: min(deadline, Date().addingTimeInterval(1))) { return }
        // If Slack is still rendering the menu during the first press, refresh
        // the owned Accessibility session and reverify that same menu before retrying.
        if let rebuild = tree.rebuildOwnedMode { try rebuild(deadline) }
        if let visible = try currentMenu(in: tree) { try dismiss(visible) }
        guard try dismissed(until: deadline) else { throw RemoteError.overlayLeftOpen }
    }

    private static func loaded(team: TeamID, in tree: SlackTree) throws -> View? {
        guard let view = try current(team: team, in: tree) else { return nil }
        if view.scope != nil {
            let lists = view.root.all(Locators.scopedSearchList) + view.root.all(Locators.scopedSearchMatches)
            guard lists.count == 1, let list = lists.first,
                  !list.children.contains(where: { $0.domID == Locators.scopedSearchLoadingID }) else { return nil }
        } else if view.root.all(Locators.searchResultList).isEmpty
                    && !view.root.descendants().contains(where: { $0.domClasses.contains(Locators.searchResultEmpty) }) {
            return nil
        }
        return view
    }

    private static func dismissScoped(in tree: SlackTree, deadline: Date) throws {
        try tree.refresh()
        let header = try SlackWindow.currentWindow(in: tree).window.all(Locators.scopedSearchHeader)
        guard !header.isEmpty else { return }
        guard header.count == 1, let root = header.first else {
            throw RemoteError.uiDrift(locator: Locators.scopedSearchHeader.name, found: header.count)
        }
        let close = try root.one(Locators.scopedSearchClose)
        guard close.actionNames.contains(UIAction.press.rawValue) else {
            throw RemoteError.uiDrift(locator: Locators.scopedSearchClose.name, found: 0)
        }
        guard Date() < deadline else { throw RemoteError.overlayLeftOpen }
        try? close.perform(.press)
        guard try Poll.until(deadline, {
            try tree.refresh()
            return try SlackWindow.currentWindow(in: tree).window.all(Locators.scopedSearchHeader).isEmpty ? true : nil
        }) == true else { throw RemoteError.overlayLeftOpen }
    }

    private static func clearActiveQuery(in tree: SlackTree, deadline: Date) throws {
        try tree.refresh()
        let buttons = try SlackWindow.currentWindow(in: tree).window.all(Locators.searchTopClear)
        guard buttons.count <= 1 else { throw RemoteError.uiDrift(locator: Locators.searchTopClear.name, found: buttons.count) }
        guard let clear = buttons.first else { return }
        guard Date() < deadline else { throw RemoteError.overlayLeftOpen }
        try? clear.perform(.press)
        guard try Poll.until(deadline, {
            try tree.refresh()
            return try SlackWindow.currentWindow(in: tree).window.all(Locators.searchTopClear).isEmpty ? true : nil
        }) == true else { throw RemoteError.overlayLeftOpen }
    }

    private static func rendered(type: String, in view: View)
        throws -> [(key: RowKey, node: any UINode, item: Row)] {
        let root = view.root
        if root.descendants().contains(where: { $0.domClasses.contains(Locators.searchResultEmpty) }) { return [] }
        let list = try root.one(view.scope == nil ? Locators.searchResultList : Locators.scopedSearchMatches)
        let rowClass = view.scope == nil ? Locators.searchResultRow : "c-virtual_list__item"
        let rows = list.children.filter { $0.domClasses.contains(rowClass) }
        var occurrences: [Content: Int] = [:]
        return rows.map { node in
            let contents = content(type: type, row: node)
            let occurrence = occurrences[contents, default: 0]
            occurrences[contents] = occurrence + 1
            let id = node.domID.flatMap { $0.isEmpty ? nil : $0 }
            let key = id.map(RowKey.domID) ?? .sameContent(contents, occurrence: occurrence)
            return (key, node, Row(key: key, content: contents))
        }
    }

    static func content(type: String, row: any UINode) -> Content {
        let nodes = row.descendants()
        switch type {
        case "messages":
            let links = nodes.filter(Locators.searchTimestamp.matches)
            let identity = links.count == 1 ? links.first?.string(.url).flatMap(messagePermalink) : nil
            let buttons = nodes.filter(Locators.senderButton.matches)
            let sender = buttons.count == 1 ? buttons[0].string(.title) : nil
            let sections = nodes.filter(Locators.richTextSection.matches).map { section in
                section.descendants().compactMap { $0.role == "AXStaticText" ? $0.string(.value) : nil }.joined()
            }
            return .message(identity, sender: sender, text: sections.joined(separator: "\n"))
        case "files":
            let file = uniqueIdentity(in: [row] + nodes, fromID: fileID, fromLink: fileLinkID)
            let conversation = file.flatMap { _ in
                uniqueIdentity(in: nodes, fromID: { ConversationID($0) }, fromLink: conversationLinkID)
            }
            return .file(file, name: displayText(row, descendants: nodes), conversation: conversation)
        case "channels":
            let conversation = uniqueIdentity(in: [row] + nodes, fromID: { ConversationID($0) }, fromLink: conversationLinkID)
            return .channel(conversation, name: displayText(row, descendants: nodes))
        case "people":
            let user = uniqueIdentity(in: [row] + nodes, fromID: { UserID($0) }, fromLink: { url in
                let components = url.percentEncodedPath.split(separator: "/")
                guard url.host == "app.slack.com", components.count == 2, components[0] == "team" else { return nil }
                return UserID(String(components[1]))
            })
            return .person(user, label: displayText(row, descendants: nodes))
        default:
            return .other(label: displayText(row, descendants: nodes))
        }
    }

    private static func messagePermalink(_ raw: String) -> MessageIdentity? {
        guard let url = slackLink(raw),
              let match = url.percentEncodedPath.wholeMatch(of: #/\/archives\/([CDG][A-Z0-9]{8,})\/p([0-9]{10})([0-9]{6})/#),
              let conversation = ConversationID(String(match.1)) else { return nil }
        return MessageIdentity(conversation: conversation, ts: "\(match.2).\(match.3)")
    }

    private static func slackLink(_ raw: String) -> URLComponents? {
        guard let url = URLComponents(string: raw), url.scheme == "https", let host = url.host,
              host.hasSuffix(".slack.com"), url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    private static func uniqueIdentity<ID: Hashable>(in nodes: [any UINode], fromID: (String) -> ID?,
                                                      fromLink: (URLComponents) -> ID?) -> ID? {
        let ids = Set(nodes.compactMap { node -> ID? in
            if let id = node.domID.flatMap(fromID) { return id }
            guard node.role == "AXLink", let link = node.string(.url).flatMap(slackLink) else { return nil }
            return fromLink(link)
        })
        return ids.count == 1 ? ids.first : nil
    }

    private static func fileID(_ raw: String) -> String? {
        raw.wholeMatch(of: #/F[A-Z0-9]{8,}/#).map { String($0.output) }
    }

    private static func fileLinkID(_ url: URLComponents) -> String? {
        let parts = url.percentEncodedPath.split(separator: "/")
        if url.host == "app.slack.com", parts.count >= 3, parts[0] == "files", TeamID(String(parts[1])) != nil {
            return fileID(String(parts[2]))
        }
        if url.host == "files.slack.com", parts.count >= 2, parts[0] == "files-pri",
           let match = parts[1].wholeMatch(of: #/([TE][A-Z0-9]{8,})-(F[A-Z0-9]{8,})/#) {
            return String(match.2)
        }
        return nil
    }

    private static func conversationLinkID(_ url: URLComponents) -> ConversationID? {
        let parts = url.percentEncodedPath.split(separator: "/")
        if parts.count == 2, parts[0] == "archives" { return ConversationID(String(parts[1])) }
        return ClientLocation.parse(url: url.string ?? "").destination?.conversation
    }

    private static func displayText(_ row: any UINode, descendants: [any UINode]) -> String? {
        if let title = row.string(.title), !title.isEmpty { return title }
        return descendants.lazy.compactMap { node in
            node.role == "AXStaticText" ? node.string(.value) : nil
        }.first { !$0.isEmpty }
    }
}
