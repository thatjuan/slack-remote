import Foundation

public struct DryRun: Encodable {
    public enum Operation {
        case open
        case draftSet(String)
        case draftClear(String)
        case send(String)
        case readThread(rootTs: String, history: Bool, close: Bool)
        case reply(rootTs: String, text: String, broadcast: Bool)
        case react(ts: String, thread: String?)
        case upload(file: FileStaging.File, text: String?, thread: String?, broadcast: Bool)
    }

    public enum ComposerStatus: String, Encodable { case empty, text, pending, unknown }

    public let dryRun = true
    public let team: TeamID
    public let conversation: ConversationID
    public let atDestination: Bool
    public let account: Account.Verification
    public let composer: ComposerStatus
    public let file: FileStaging.File?
    public let plan: [String]

    public static func preview(_ operation: Operation, destination: Destination, user: UserID?,
                               preference: Navigator.RoutePreference, config: Config?,
                               in tree: SlackTree, deadline: Date,
                               warn: (String) -> Void = { _ in }) throws -> DryRun {
        let access: Account.Access
        switch operation {
        case .open, .readThread: access = .read
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
            let scope: MessageScope?
            switch operation {
            case .reply(let rootTs, _, _):
                scope = (try? ThreadView.verify(rootTs: rootTs, in: view)).map(MessageScope.thread)
            case .upload(_, _, let rootTs?, _):
                scope = (try? ThreadView.verify(rootTs: rootTs, in: view)).map(MessageScope.thread)
            case .readThread, .react:
                scope = nil
            default:
                scope = .primary
            }
            if let scope {
                let controls = try Composer(view: view, scope: scope, in: nil, methods: .live).controls(in: view)
                state = try controls.state()
                sendEnabled = controls.enabled
            }
            try Composer.requireLiveDestination(view)
        } else if preference == .sidebar {
            try Navigator.requireSidebarTarget(for: destination, in: client)
        }

        var file: FileStaging.File?
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
        case .readThread(let rootTs, let history, let close):
            plan.append("open and verify thread \(rootTs)")
            plan.append(history ? "page thread history" : "read rendered thread")
            if close { plan.append("close verified thread") }
        case .reply(let rootTs, let text, let broadcast):
            plan.append("open and verify thread \(rootTs)")
            try requireCompatibleDraft(state, text: text)
            if state == .text(MessageText.normalize(text)) {
                guard sendEnabled == true else { throw RemoteError.writeUnverified(draftLeft: true) }
                plan.append("reuse matching thread draft")
            } else {
                plan.append("write text (\(text.count) characters)")
            }
            plan += [broadcast ? "verify broadcast enabled" : "verify broadcast disabled",
                     "final gate", "press send once", "confirm reply"]
        case .react(let ts, let rootTs):
            if let rootTs { plan.append("open and verify thread \(rootTs)") }
            plan += ["locate message \(ts)", "check existing reactions", "open emoji picker",
                     "verify message and exact emoji cell", "press emoji once if needed", "confirm reaction"]
        case .upload(let candidate, let text, let rootTs, let broadcast):
            if let state, state != .empty { throw Composer.conflict(state) }
            file = candidate
            if let rootTs { plan.append("open and verify thread \(rootTs)") }
            plan += ["require an empty composer", "stage the file", "attach the exact staged file URL"]
            if let text { plan.append("write text (\(text.count) characters)") }
            if rootTs != nil { plan.append(broadcast ? "verify broadcast enabled" : "verify broadcast disabled") }
            plan += ["final gate", "press send once", "confirm attachment", "remove staged copy"]
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
                      atDestination: atDestination, account: account, composer: composer, file: file, plan: plan)
    }

    private static func requireCompatibleDraft(_ state: ComposerState?, text: String) throws {
        guard let state, state != .empty, state != .text(MessageText.normalize(text)) else { return }
        throw Composer.conflict(state)
    }
}
