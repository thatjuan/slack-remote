import Foundation
@testable import SlackRemoteCore

/// Sets up the same team, viewer and cache for the read operation fixtures.
struct ReadCommandFixtures {
    static let team = TeamID("T00000001")!
    static let viewer = UserID("U00000001")!
    static let channel = ConversationID("C00000001")!
    static let destination = Destination(team: team, conversation: channel)

    let transport: SlackAPITests.StubTransport
    let api: SlackAPI
    let directory: UserDirectory
    let deadline: Date

    init(_ json: String..., seconds: Double = 10) {
        transport = SlackAPITests.StubTransport(json.map { .success(.init(status: 200, body: Data($0.utf8))) })
        deadline = Date().addingTimeInterval(seconds)
        api = SlackAPI(team: Self.team, user: Self.viewer, transport: transport, deadline: deadline)
        directory = UserDirectory(api: api)
    }

    func context(warn: @escaping @Sendable (String) -> Void = { _ in }) -> OperationContext {
        OperationContext(deadline: deadline, config: nil, helperVersion: "2.0.0", accounts: {
            [.init(id: AccountID(), teams: [.init(id: Self.team, name: "Example", url: URL(string: "https://example.slack.com")!,
                                 user: Self.viewer, userName: "Viewer")], state: .active, addedAt: Date())]
        }, api: { _ in api }, users: { _ in directory },
        ui: .init(add: { _, _ in nil }, remove: { _ in }), warn: warn)
    }
}
