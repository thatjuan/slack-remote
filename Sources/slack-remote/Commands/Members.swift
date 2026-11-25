import ArgumentParser
import SlackRemoteCore

struct MemberListingResult: Encodable {
    let team: TeamID
    var conversation: ConversationID? = nil
    let snapshot: MemberList.Snapshot

    private enum CodingKeys: String, CodingKey {
        case team, conversation, complete, stopReason, pages, expectedCount, members
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(team, forKey: .team)
        try fields.encodeIfPresent(conversation, forKey: .conversation)
        try fields.encode(snapshot.listing.complete, forKey: .complete)
        try fields.encode(snapshot.listing.stopReason, forKey: .stopReason)
        try fields.encode(snapshot.listing.pages, forKey: .pages)
        try fields.encode(snapshot.expectedCount, forKey: .expectedCount)
        try fields.encode(snapshot.listing.items, forKey: .members)
    }
}

struct Members: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List members of a Slack channel or group conversation.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var listing: ListingOptions
    @OptionGroup var target: DestinationOptions

    func validate() throws {
        try target.validate(requireDestination: true)
    }

    func run() throws {
        try listing.run("members", options: options) { app, tree, bounds in
            let config = try Config.load()
            let destination = try target.requireDestination(using: config)
            try MemberList.requireSupported(destination)
            return try Directory.restoringConversation(app: app, in: tree) {
                _ = try target.navigate(to: destination, app: app, in: tree, deadline: bounds.deadline)
                let view = try SlackWindow.verify(destination, in: tree)
                _ = try Account.verify(team: destination.team, in: tree, config: config, access: .read,
                                       deadline: bounds.deadline, window: view.window, warn: app.warn)
                try Environment.requireSlackIdle(interrupt: target.interrupt)
                let snapshot = try MemberList.read(destination, in: tree, bounds: bounds)
                return (MemberListingResult(team: destination.team, conversation: destination.conversation,
                                            snapshot: snapshot), snapshot.listing.stopReason)
            }
        }
    }
}
