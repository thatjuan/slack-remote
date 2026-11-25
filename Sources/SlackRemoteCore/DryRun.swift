import Foundation

public struct DryRun: Encodable {
    public enum Operation {
        case open
        case draftSet(String)
        case draftClear(String)
        case send(String)
    }

    public enum ComposerStatus: String, Encodable { case empty, text, pending, unknown }

    public let dryRun = true
    public let team: TeamID
    public let conversation: ConversationID
    public let atDestination: Bool
    public let account: Account.Verification
    public let composer: ComposerStatus
    public let plan: [String]

    public static func preview(_ operation: Operation, destination: Destination, user: UserID?,
                               preference: Navigator.RoutePreference, config: Config?,
                               in tree: SlackTree, deadline: Date,
                               warn: (String) -> Void = { _ in }) throws -> DryRun {
        let access: Account.Access
        switch operation {
        case .open: access = .read
        default:
            access = .dryRunWrite
            try config?.requireWriteAllowed(to: destination)
        }
        try tree.refresh()
        try Overlays.requireUnblocked(in: tree)
        let client = try SlackWindow.currentWindow(in: tree)
        let atDestination = client.location.destination == destination
        let account = try Account.verify(team: destination.team, in: tree, config: config, access: access,
                                         deadline: deadline, warn: warn)
        var state: ComposerState?
        var sendEnabled: Bool?
        let route = Navigator.plannedRoute(to: destination, user: user, preference: preference)
        var plan: [String] = []
        if !atDestination || preference == .sidebar { plan.append("navigate via \(route.rawValue)") }
        plan.append("verify destination")
        if atDestination {
            let view = try SlackWindow.verify(destination, in: tree)
            let controls = try Composer(view: view).controls(in: view)
            state = try controls.state()
            sendEnabled = controls.enabled
            try Composer.requireLiveDestination(view)
        } else if preference == .sidebar {
            try Navigator.requireSidebarTarget(for: destination, in: client)
        }

        switch operation {
        case .open:
            break
        case .draftSet(let text):
            try requireCompatibleDraft(state, text: text)
            if state == .text(MessageText.normalize(text)) { plan.append("reuse matching draft") }
            else { plan.append("write text (\(text.count) characters)") }
        case .draftClear(let expected):
            try requireCompatibleDraft(state, text: expected)
            if state == .empty { plan.append("confirm composer is empty") }
            else { plan.append("clear matching draft") }
        case .send(let text):
            try requireCompatibleDraft(state, text: text)
            if state == .text(MessageText.normalize(text)) {
                guard sendEnabled == true else { throw RemoteError.writeUnverified(draftLeft: true) }
                plan.append("reuse matching draft")
            } else {
                plan.append("write text (\(text.count) characters)")
            }
            plan += ["final gate", "press send once", "confirm message"]
        }
        let composer: ComposerStatus
        switch state {
        case .empty: composer = .empty
        case .text: composer = .text
        case .pendingContent: composer = .pending
        case nil: composer = .unknown
        }
        guard Date() < deadline else { throw RemoteError.timeout }
        return DryRun(team: destination.team, conversation: destination.conversation,
                      atDestination: atDestination, account: account, composer: composer, plan: plan)
    }

    private static func requireCompatibleDraft(_ state: ComposerState?, text: String) throws {
        guard let state, state != .empty, state != .text(MessageText.normalize(text)) else { return }
        throw Composer.conflict(state)
    }
}
