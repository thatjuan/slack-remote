import Foundation

/// Identifies the signed-in workspace and looks up the user's self-DM.
public struct WhoamiRequest: RemoteOperation, Equatable {
    public struct Output: Encodable, Sendable {
        public let team: TeamID
        public let teamName: String
        public let url: URL
        public let user: UserID
        public let userName: String
        public let selfDM: ConversationID?
        public let account: String

        private enum CodingKeys: String, CodingKey {
            case team, teamName, url, user, userName, selfDM, account
        }

        public func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(team, forKey: .team)
            try fields.encode(teamName, forKey: .teamName)
            try fields.encode(url, forKey: .url)
            try fields.encode(user, forKey: .user)
            try fields.encode(userName, forKey: .userName)
            try fields.encode(selfDM, forKey: .selfDM)
            try fields.encode(account, forKey: .account)
        }
    }

    private struct OpenConversation: Decodable {
        struct Channel: Decodable { let id: ConversationID }
        let channel: Channel
    }

    public let team: TeamID?

    public init(team: TeamID? = nil) {
        self.team = team
    }

    public func run(in context: OperationContext) async throws -> Output {
        let selection = try await AccountSelection.resolve(team, in: context.accounts())
        let api = try await context.api(selection.team.id)
        let identity = try await api.verifiedIdentity()
        let selfDM: ConversationID?
        do {
            let response = try await api.call("conversations.open", ["users": identity.userId.rawValue],
                                              as: OpenConversation.self)
            selfDM = response.channel.id
        } catch RemoteError.interrupted {
            throw RemoteError.interrupted
        } catch {
            selfDM = nil
            context.warn("self_dm_unavailable")
        }
        return Output(team: api.team, teamName: selection.team.name, url: selection.team.url, user: api.user,
                      userName: selection.team.userName, selfDM: selfDM,
                      account: selection.account.id.rawValue.uuidString)
    }
}

/// The identity returned by Slack; snake case decodes `user_id` as `userId`.
struct SlackIdentity: Decodable {
    let userId: UserID
}

extension SlackAPI {
    func verifiedIdentity() async throws -> SlackIdentity {
        let identity = try await call("auth.test", as: SlackIdentity.self)
        guard identity.userId == user else { throw RemoteError.accountMismatch }
        return identity
    }
}
