import Foundation

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
                              read: () throws -> T) throws -> T {
        try run(query: query, filters: filters, from: destination, account: account,
                in: tree, deadline: deadline, submitFallback: { _, _ in
            throw RemoteError.uiDrift(locator: "searchSubmit", found: 0)
        }, read: read)
    }

    static func run<T>(query: String, filters: Filters, from destination: Destination,
                       account: Account?, in tree: SlackTree, deadline: Date,
                       submitFallback: (any UINode, String) throws -> Void,
                       read: () throws -> T) throws -> T {
        try validate(query)
        try tree.refresh()
        let view = try SlackWindow.verify(destination, in: tree)
        let button = try view.window.one(Locators.searchButton)
        guard Date() < deadline else { throw RemoteError.timeout }

        var toggled: [String] = []
        var submitted = false
        let outcome = Result {
            try button.perform(.press)
            guard let initial = try Poll.until(deadline, { try current(in: tree) }) else { throw RemoteError.timeout }
            let initiallyActive = try activeFilters(in: initial)
            guard initiallyActive.isEmpty else {
                throw RemoteError.uiDrift(locator: "searchInitialFilters", found: initiallyActive.count)
            }
            let initialField = try initial.one(Locators.searchQuery)
            guard MessageText.normalize(initialField.string(.value) ?? "").isEmpty else {
                throw RemoteError.uiDrift(locator: "searchInitialQuery", found: 1)
            }

            let requested = try requestedFilters(filters, account: account, in: initial)
            for id in requested {
                guard Date() < deadline else { throw RemoteError.timeout }
                guard let modal = try current(in: tree) else { throw RemoteError.uiDrift(locator: "searchModal", found: 0) }
                let control = try filter(id, in: modal)
                let tokens = try tokenCount(in: modal)
                toggled.append(id)
                try control.perform(.press)
                guard try Poll.until(deadline, {
                    guard let refreshed = try current(in: tree),
                          try activeFilters(in: refreshed).contains(id),
                          try tokenCount(in: refreshed) == tokens + 1 else { return nil as Bool? }
                    return true
                }) == true else { throw RemoteError.uiDrift(locator: "searchFilterToken", found: 0) }
            }

            guard let modal = try current(in: tree) else { throw RemoteError.uiDrift(locator: "searchModal", found: 0) }
            let field = try modal.one(Locators.searchQuery)
            try field.set(.focused, to: .bool(true))
            let baseline = field.string(.value) ?? ""
            try field.set(.selectedText, to: .string(query))

            guard let ready = try current(in: tree) else { throw RemoteError.uiDrift(locator: "searchModal", found: 0) }
            let readyField = try ready.one(Locators.searchQuery)
            guard matches(query, after: baseline, in: readyField),
                  try activeFilters(in: ready) == Set(requested),
                  try tokenCount(in: ready) == requested.count else {
                throw RemoteError.uiDrift(locator: "searchQueryReadback", found: 0)
            }
            guard Date() < deadline else { throw RemoteError.timeout }
            let submitRows = ready.descendants().filter {
                $0.domClasses.contains(Locators.searchQuerySuggestionClass)
                    && $0.actionNames.contains(UIAction.press.rawValue)
            }
            guard submitRows.count <= 1 else {
                throw RemoteError.uiDrift(locator: "searchSubmit", found: submitRows.count)
            }
            if let semantic = submitRows.first {
                try semantic.perform(.press)
            } else {
                try submitFallback(readyField, baseline)
            }
            submitted = true
            return try read()
        }
        try close(in: tree, rollback: submitted ? [] : toggled)
        return try outcome.get()
    }

    static func matches(_ query: String, after baseline: String, in field: any UINode) -> Bool {
        guard let observed = field.string(.value) else { return false }
        return MessageText.normalize(observed) == MessageText.normalize(MessageText.normalize(baseline) + query)
    }

    private static func current(in tree: SlackTree) throws -> (any UINode)? {
        try tree.refresh()
        let window = try SlackWindow.currentWindow(in: tree).window
        let wrappers = window.all(Locators.searchWrapper)
        guard wrappers.count <= 1 else { throw RemoteError.uiDrift(locator: Locators.searchWrapper.name, found: wrappers.count) }
        guard !Overlays.open(in: tree).contains(.sheet) else { throw RemoteError.uiBlocked }
        return wrappers.first
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

    private static func activeFilters(in modal: any UINode) throws -> Set<String> {
        Set(modal.all(Locators.searchFilter).compactMap { $0.bool(.value) == true ? $0.domID : nil })
    }

    private static func tokenCount(in modal: any UINode) throws -> Int {
        try modal.one(Locators.searchQuery).descendants().filter {
            $0.domClasses.contains(Locators.searchFilterToken)
        }.count
    }

    private static func close(in tree: SlackTree, rollback: [String]) throws {
        do {
            let cleanupDeadline = Date().addingTimeInterval(3)
            if let modal = try current(in: tree) {
                var rollbackError: (any Error)?
                for id in rollback.reversed() {
                    do {
                        guard let refreshed = try current(in: tree) else { break }
                        if try activeFilters(in: refreshed).contains(id) {
                            try filter(id, in: refreshed).perform(.press)
                        }
                    } catch { rollbackError = error }
                }
                let clear = try (current(in: tree) ?? modal).all(Locators.searchClear)
                if clear.count == 1 { try clear.first?.perform(.press) }
                guard clear.count <= 1 else { throw RemoteError.overlayLeftOpen }
                if try current(in: tree) != nil {
                    try Overlays.closeModal(in: tree, deadline: cleanupDeadline)
                }
                if let rollbackError { throw rollbackError }
            }
            try tree.refresh()
            guard Overlays.open(in: tree).isEmpty else { throw RemoteError.overlayLeftOpen }
        } catch {
            throw RemoteError.overlayLeftOpen
        }
    }
}
