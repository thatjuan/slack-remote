import Foundation

struct SearchPopup {
    let node: any UINode

    func matches(_ candidate: any UINode) -> Bool {
        if let original = node as? AXNode, let refreshed = candidate as? AXNode {
            return original.referencesSameElement(as: refreshed)
        }
        return node as AnyObject === candidate as AnyObject
    }
}

public enum SearchModal {
    public struct Filters: Encodable {
        public let conversation: ConversationID?
        public let fromMe: Bool
        public let hasLink: Bool
        public let threadsOnly: Bool

        public init(conversation: ConversationID?, fromMe: Bool, hasLink: Bool, threadsOnly: Bool) {
            self.conversation = conversation
            self.fromMe = fromMe
            self.hasLink = hasLink
            self.threadsOnly = threadsOnly
        }

        private enum CodingKeys: String, CodingKey {
            case conversation = "in"
            case fromMe, hasLink, threadsOnly
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(conversation, forKey: .conversation)
            try container.encode(fromMe, forKey: .fromMe)
            try container.encode(hasLink, forKey: .hasLink)
            try container.encode(threadsOnly, forKey: .threadsOnly)
        }
    }

    public static func validate(_ query: String) throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteError.unsafeText(reason: "blank_query")
        }
        guard !query.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw RemoteError.unsafeText(reason: "control_character")
        }
    }

    /// Search is the only modal that may close itself into a results view.
    public static func run<T>(query: String, filters: Filters, from destination: Destination,
                              account: Account?, in tree: SlackTree, deadline: Date,
                              onOpen: () -> Void = {},
                              read: () throws -> T) throws -> T {
        try validate(query)
        try tree.refresh()
        guard filters.conversation.map({ $0 == destination.conversation }) ?? true else {
            throw RemoteError.uiDrift(locator: Locators.searchFilter.name, found: 0)
        }
        let view = try SlackWindow.verify(destination, in: tree)
        let start = try SlackWindow.currentWindow(in: tree)
        guard start.location.destination == destination else {
            throw RemoteError.destinationMismatch(expected: destination, actual: start.location)
        }
        let button = try view.window.one(Locators.searchButton)
        guard Date() < deadline else { throw RemoteError.timeout }

        var toggled: [String] = []
        var openingAttempted = false
        var queryWriteAttempted = false
        var submitted = false
        var owned: SearchPopup?
        let outcome = Result {
            try tree.checkInterruption()
            openingAttempted = true
            try button.perform(.press)
            guard let opened = try Poll.until(deadline, { try openedFrom(start, in: tree) }) else {
                throw RemoteError.timeout
            }
            owned = SearchPopup(node: opened)
            onOpen()
            try tree.checkInterruption()
            let openedField = try opened.one(Locators.searchQuery)
            if !MessageText.normalize(openedField.string(.value) ?? "").isEmpty || !activeFilters(in: opened).isEmpty {
                try opened.one(Locators.searchClear).perform(.press)
            }
            guard let initial = try Poll.until(deadline, {
                guard let modal = try current(in: tree), activeFilters(in: modal).isEmpty,
                      try tokenCount(in: modal) == 0,
                      MessageText.normalize(try modal.one(Locators.searchQuery).string(.value) ?? "").isEmpty else {
                    return nil as (any UINode)?
                }
                return modal
            }) else { throw RemoteError.uiDrift(locator: "searchInitialQuery", found: 1) }

            let requested = try requestedFilters(filters, account: account, in: initial)

            func changeFilter(_ id: String, enabled: Bool) throws {
                guard Date() < deadline else { throw RemoteError.timeout }
                guard let modal = try current(in: tree) else {
                    throw RemoteError.uiDrift(locator: Locators.searchModal.name, found: 0)
                }
                var expected = activeFilters(in: modal)
                guard expected.contains(id) != enabled else {
                    throw RemoteError.uiDrift(locator: "searchFilterState", found: expected.count)
                }
                if enabled {
                    toggled.append(id)
                    expected.insert(id)
                } else {
                    expected.remove(id)
                }
                let control = try filter(id, in: modal)
                try tree.checkInterruption()
                try control.perform(.press)
                guard try Poll.until(deadline, {
                    guard let refreshed = try current(in: tree), activeFilters(in: refreshed) == expected,
                          try tokenCount(in: refreshed) == expected.count else { return nil as Bool? }
                    return true
                }) == true else { throw RemoteError.uiDrift(locator: "searchFilterToken", found: 0) }
                if !enabled { toggled.removeAll { $0 == id } }
            }

            // AXValue writes the query but replaces Quill's filter chips. Capture their
            // serialization, write into the empty field, then reapply the same native filters.
            for id in requested { try changeFilter(id, enabled: true) }
            guard let filterOnly = try current(in: tree)?.one(Locators.searchQuery).string(.value) else {
                throw RemoteError.uiDrift(locator: "searchFilterReadback", found: 0)
            }
            let filterText = MessageText.normalize(filterOnly)
            for id in requested.reversed() { try changeFilter(id, enabled: false) }

            guard let field = try current(in: tree)?.one(Locators.searchQuery),
                  MessageText.normalize(field.string(.value) ?? "").isEmpty, field.isSettable(.value) else {
                throw RemoteError.uiDrift(locator: Locators.searchQuery.name, found: 0)
            }
            guard Date() < deadline else { throw RemoteError.timeout }
            try tree.checkInterruption()
            queryWriteAttempted = true
            try field.set(.value, to: .string(query))
            let plain: Bool? = try Poll.until(min(deadline, Date().addingTimeInterval(2))) {
                guard let field = try current(in: tree)?.one(Locators.searchQuery),
                      matches(query, followedBy: "", in: field) else { return nil }
                return true
            }
            guard plain == true else { throw RemoteError.uiDrift(locator: "searchQueryReadback", found: 0) }
            for id in requested { try changeFilter(id, enabled: true) }

            let filterSuffix = requested.isEmpty ? "" : " " + filterText
            guard let ready = try current(in: tree) else { throw RemoteError.uiDrift(locator: "searchModal", found: 0) }
            let readyField = try ready.one(Locators.searchQuery)
            guard matches(query, followedBy: filterSuffix, in: readyField),
                  try filtersMatch(requested, in: ready) else {
                throw RemoteError.uiDrift(locator: "searchQueryReadback", found: 0)
            }
            guard let submit = try Poll.until(deadline, {
                guard let modal = try current(in: tree), let field = try? modal.one(Locators.searchQuery),
                      matches(query, followedBy: filterSuffix, in: field),
                      try filtersMatch(requested, in: modal) else {
                    throw RemoteError.uiDrift(locator: "searchQueryReadback", found: 0)
                }
                let candidates = modal.descendants().filter {
                    $0.domClasses.contains(Locators.searchQuerySuggestionClass)
                        && $0.actionNames.contains(UIAction.press.rawValue)
                }
                let selected = candidates.count <= 1 ? candidates : candidates.filter {
                    $0.domClasses.contains(Locators.searchSuggestionSelected)
                }
                guard selected.count <= 1 else { throw RemoteError.uiDrift(locator: "searchSubmit", found: selected.count) }
                return selected.first
            }) else { throw RemoteError.uiDrift(locator: "searchSubmit", found: 0) }
            try tree.checkInterruption()
            try submit.perform(.press)
            submitted = true
            return try read()
        }
        try tree.withCleanup {
            if openingAttempted, owned == nil {
                // Slack can render the popup after AXPress returns or after the signal interrupts a refresh.
                // The starting window and location must still match before taking ownership.
                do {
                    if let opened = try Poll.until(tree.cleanupDeadline(after: 2), { try openedFrom(start, in: tree) }) {
                        owned = SearchPopup(node: opened)
                    }
                } catch {
                    throw RemoteError.overlayLeftOpen
                }
            }
            try close(in: tree, owned: owned, rollback: submitted ? [] : toggled, clearQuery: queryWriteAttempted)
        }
        try tree.checkInterruption()
        return try outcome.get()
    }

    static func matches(_ query: String, followedBy suffix: String, in field: any UINode) -> Bool {
        guard let observed = field.string(.value) else { return false }
        return MessageText.normalize(observed) == MessageText.normalize(query + suffix)
    }

    private static func current(in tree: SlackTree) throws -> (any UINode)? {
        try tree.refresh()
        let window = try SlackWindow.currentWindow(in: tree).window
        return try modal(in: window, tree: tree)
    }

    private static func openedFrom(_ start: ClientWindow, in tree: SlackTree) throws -> (any UINode)? {
        try tree.refresh()
        let current = try SlackWindow.currentWindow(in: tree)
        guard current.location == start.location, SearchPopup(node: start.window).matches(current.window) else {
            throw RemoteError.uiDrift(locator: Locators.searchModal.name, found: 0)
        }
        guard let modal = try modal(in: current.window, tree: tree),
              modal.all(Locators.searchQuery).count == 1 else { return nil }
        return modal
    }

    private static func modal(in window: any UINode, tree: SlackTree) throws -> (any UINode)? {
        let modals = window.descendants().filter { node in
            Locators.searchModal.matches(node)
                || (node.domClasses.contains(Locators.modalContent) && node.all(Locators.searchWrapper).count == 1)
        }
        guard modals.count <= 1 else {
            throw RemoteError.uiDrift(locator: Locators.searchModal.name, found: modals.count)
        }
        guard !Overlays.open(in: tree).contains(.sheet) else { throw RemoteError.uiBlocked }
        return modals.first
    }

    private static func requestedFilters(_ filters: Filters, account: Account?, in modal: any UINode) throws -> [String] {
        var ids: [String] = []
        if let conversation = filters.conversation {
            let suffix: String
            if conversation.kind == .directMessage {
                // The quick filter in a self-DM is keyed by the signed-in user's ID.
                guard let account, account.selfDM == conversation else { throw RemoteError.unsupportedDestination }
                suffix = account.user.rawValue
            } else {
                suffix = conversation.rawValue
            }
            ids.append("quick-filter-in-" + suffix)
        }
        if filters.fromMe {
            let controls = modal.all(Locators.selfFilter)
            guard controls.count == 1, let id = controls.first?.domID,
                  let user = UserID(String(id.dropFirst(Locators.selfFilterPrefix.count))),
                  account.map({ $0.user == user }) ?? true else {
                throw RemoteError.uiDrift(locator: Locators.selfFilter.name, found: controls.count)
            }
            ids.append(id)
        }
        if filters.hasLink { ids.append("quick-filter-has-link") }
        if filters.threadsOnly { ids.append("quick-filter-is-thread") }
        return ids
    }

    private static func filter(_ id: String, in modal: any UINode) throws -> any UINode {
        let controls = modal.all(Locators.searchFilter).filter { $0.domID == id }
        guard controls.count == 1, let control = controls.first,
              control.actionNames.contains(UIAction.press.rawValue) else {
            throw RemoteError.uiDrift(locator: Locators.searchFilter.name, found: controls.count)
        }
        return control
    }

    private static func activeFilters(in modal: any UINode) -> Set<String> {
        Set(modal.all(Locators.searchFilter).compactMap {
            $0.domClasses.contains(Locators.searchFilterActive) ? $0.domID : nil
        })
    }

    private static func tokenCount(in modal: any UINode) throws -> Int {
        try modal.one(Locators.searchQuery).descendants().filter {
            $0.domClasses.contains(Locators.searchFilterToken)
        }.count
    }

    private static func filtersMatch(_ requested: [String], in modal: any UINode) throws -> Bool {
        if requested.isEmpty { return true }
        let count = try tokenCount(in: modal)
        return activeFilters(in: modal) == Set(requested) && count == requested.count
    }

    private static func close(in tree: SlackTree, owned: SearchPopup?, rollback: [String], clearQuery: Bool) throws {
        var fieldCleanupError: (any Error)?
        do {
            let cleanupDeadline = tree.cleanupDeadline(after: 4)
            func ownedModal() throws -> (client: ClientWindow, node: any UINode)? {
                try tree.refresh()
                let client = try SlackWindow.currentWindow(in: tree)
                guard let modal = try modal(in: client.window, tree: tree) else { return nil }
                guard owned?.matches(modal) == true else { throw RemoteError.overlayLeftOpen }
                return (client, modal)
            }
            func requireTime() throws {
                guard Date() < cleanupDeadline else { throw RemoteError.overlayLeftOpen }
            }
            var visible = try ownedModal()
            for id in rollback.reversed() {
                guard let node = visible?.node else { break }
                if activeFilters(in: node).contains(id) {
                    try requireTime()
                    do { try filter(id, in: node).perform(.press) }
                    catch { fieldCleanupError = error }
                    visible = try ownedModal()
                }
            }
            if clearQuery, let node = visible?.node {
                let clear = node.all(Locators.searchClear)
                guard clear.count <= 1 else { throw RemoteError.overlayLeftOpen }
                if let button = clear.first {
                    try requireTime()
                    do { try button.perform(.press) }
                    catch { fieldCleanupError = error }
                    visible = try ownedModal()
                }
            }
            if let owned, let original = visible?.client.location {
                func dismissControl(in client: ClientWindow, popup: any UINode) -> (any UINode)? {
                    let buttons = popup.all(Locators.searchClose)
                    if buttons.count == 1 { return buttons.first }
                    return ownedBackdrop(owned, in: client.window)
                }
                var target = visible.flatMap { dismissControl(in: $0.client, popup: $0.node) }
                if target == nil {
                    // Slack can render the search field before it exposes the dismiss control.
                    _ = try Poll.until(min(cleanupDeadline, Date().addingTimeInterval(0.6))) { () -> Bool? in
                        visible = try ownedModal()
                        guard let visible else { return true }
                        target = dismissControl(in: visible.client, popup: visible.node)
                        return target == nil ? nil : true
                    }
                }
                if target == nil, visible != nil, let rebuild = tree.rebuildOwnedMode {
                    try rebuild(cleanupDeadline)
                    visible = try ownedModal()
                    target = visible.flatMap { dismissControl(in: $0.client, popup: $0.node) }
                }
                if let visible {
                    guard visible.client.location == original, let target else { throw RemoteError.overlayLeftOpen }
                    try requireTime()
                    try? target.perform(.press)
                    if Locators.searchClose.matches(target), let stillOpen = try ownedModal(),
                       stillOpen.client.location == original,
                       let backdrop = ownedBackdrop(owned, in: stillOpen.client.window) {
                        try requireTime()
                        try? backdrop.perform(.press)
                    }
                    guard try Poll.until(cleanupDeadline, {
                        try ownedModal() == nil ? true : nil
                    }) == true else { throw RemoteError.overlayLeftOpen }
                }
            }
            try tree.refresh()
            guard Overlays.open(in: tree).isEmpty else { throw RemoteError.overlayLeftOpen }
        } catch {
            throw RemoteError.overlayLeftOpen
        }
        if let fieldCleanupError { throw fieldCleanupError }
    }

    private static func ownedBackdrop(_ popup: SearchPopup, in window: any UINode) -> (any UINode)? {
        let associated = window.all(Locators.modalOverlay).filter {
            $0.all(Locators.informationalTooltip).isEmpty && $0.descendants().contains(where: popup.matches)
        }
        return associated.count == 1 ? associated.first : nil
    }
}
