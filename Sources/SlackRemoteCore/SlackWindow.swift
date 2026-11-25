public struct ClientWindow {
    public let window: any UINode
    public let location: ClientLocation
    fileprivate let locations: [ClientLocation]

    fileprivate init(window: any UINode, location: ClientLocation, locations: [ClientLocation]) {
        self.window = window
        self.location = location
        self.locations = locations
    }
}

public struct VerifiedView {
    public let destination: Destination
    public let window: any UINode
    public let primaryView: any UINode
    let passiveSelfPreview: PassiveSelfPreview?

    init(destination: Destination, window: any UINode, primaryView: any UINode,
         passiveSelfPreview: PassiveSelfPreview? = nil) {
        self.destination = destination
        self.window = window
        self.primaryView = primaryView
        self.passiveSelfPreview = passiveSelfPreview
    }
}

public enum SlackWindow {
    /// Find windows with a web area in the Slack client.
    public static func clientWindows(in tree: SlackTree) -> [ClientWindow] {
        tree.windows.compactMap { window in
            let locations = window.all(Locators.webArea)
                .compactMap { $0.string(.url) }
                .map(ClientLocation.parse)
                .filter { $0 != .notClient }
            guard let location = locations.first else { return nil }
            return ClientWindow(window: window, location: location, locations: locations)
        }
    }

    /// Pick the only client window, or the only one marked main.
    public static func currentWindow(in tree: SlackTree) throws -> ClientWindow {
        let clients = clientWindows(in: tree)
        guard !clients.isEmpty else { throw RemoteError.slackNotReady }
        let candidates = clients.count == 1 ? clients : clients.filter { $0.window.bool(.main) == true }
        guard candidates.count == 1, let current = candidates.first else { throw RemoteError.ambiguousWindow }
        try requireAvailable(current.window)
        return current
    }

    /// Require the exact workspace and conversation, then check the window structure and sidebar selection.
    public static func verify(_ destination: Destination, in tree: SlackTree) throws -> VerifiedView {
        try verify(destination, in: tree, allowingModalContaining: nil)
    }

    public static func verifyForReading(_ destination: Destination, in tree: SlackTree) throws -> VerifiedView {
        try Overlays.requireUnblockedForConversationRead(in: tree)
        return try verifyDestination(destination, in: tree)
    }

    public static func verifyPrimaryWrite(_ destination: Destination, in tree: SlackTree,
                                          config: Config?) throws -> VerifiedView {
        if Overlays.open(in: tree).isEmpty { return try verifyDestination(destination, in: tree) }
        guard let account = config?.accounts.first(where: { $0.team == destination.team }),
              account.selfDM == destination.conversation else { throw RemoteError.uiBlocked }
        return try PassiveSelfPreview.bind(destination, in: tree, account: account)
    }

    public static func reverifyWrite(_ view: VerifiedView, in tree: SlackTree) throws -> VerifiedView {
        if let preview = view.passiveSelfPreview { return try preview.verify(view.destination, in: tree) }
        return try verify(view.destination, in: tree)
    }

    static func verify(_ destination: Destination, in tree: SlackTree,
                       allowingModalContaining locator: Locator?) throws -> VerifiedView {
        if let locator {
            _ = try Overlays.requireOnlyModal(containing: locator, in: tree)
            let current = try currentWindow(in: tree)
            guard current.location.destination == destination else {
                throw RemoteError.destinationMismatch(expected: destination, actual: current.location)
            }
        } else {
            try Overlays.requireUnblocked(in: tree)
        }
        return try verifyDestination(destination, in: tree)
    }

    static func verifyDestination(_ destination: Destination, in tree: SlackTree) throws -> VerifiedView {
        let clients = clientWindows(in: tree)
        let matching = clients.filter { client in
            client.locations.contains { $0.destination == destination }
        }
        guard matching.count <= 1 else { throw RemoteError.ambiguousWindow }
        guard let client = matching.first else {
            throw RemoteError.destinationMismatch(expected: destination, actual: observedLocation(in: clients))
        }
        try requireAvailable(client.window)
        _ = try client.window.one(Locators.webArea)
        let primaryView = try client.window.one(Locators.primaryView)
        let selected = client.window.all(Locators.sidebarRow).filter {
            $0.domClasses.contains(Locators.sidebarRowSelected)
        }
        guard selected.allSatisfy({ $0.domID == destination.conversation.rawValue }) else {
            throw RemoteError.destinationMismatch(expected: destination, actual: client.location)
        }
        return VerifiedView(destination: destination, window: client.window, primaryView: primaryView)
    }

    static func observedLocation(in clients: [ClientWindow]) -> ClientLocation {
        if clients.count == 1, let client = clients.first { return client.location }
        let main = clients.filter { $0.window.bool(.main) == true }
        return main.count == 1 ? main[0].location : .notClient
    }

    private static func requireAvailable(_ window: any UINode) throws {
        guard window.bool(.minimized) != true else { throw RemoteError.slackWindowUnavailable }
    }
}
