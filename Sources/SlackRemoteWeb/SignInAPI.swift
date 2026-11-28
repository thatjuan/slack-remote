import Foundation
import SlackRemoteCore
import WebKit

/// The two Slack API calls needed to verify and label a newly signed-in workspace.
@MainActor
enum SignInAPI {
    struct Identity: Decodable {
        let ok: Bool
        let user: UserID?
        let team: String?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case ok, team, url
            case user = "user_id"
        }
    }

    private struct UserInfo: Decodable {
        struct User: Decodable {
            struct Profile: Decodable {
                let displayName: String?
                let realName: String?

                enum CodingKeys: String, CodingKey {
                    case displayName = "display_name"
                    case realName = "real_name"
                }
            }
            let profile: Profile
        }
        let ok: Bool
        let user: User?
    }

    static func identity(for team: LocalConfig.Team, in store: WKWebsiteDataStore) async throws -> Identity {
        try await request(Identity.self, team: team, in: store, method: "auth.test")
    }

    /// Read the verified user's display name for the account menu.
    static func workspace(for team: LocalConfig.Team, in store: WKWebsiteDataStore) async throws -> AccountRecord.Team {
        let identity = try await identity(for: team, in: store)
        guard identity.ok, let id = TeamID(team.id), let user = identity.user, let name = identity.team,
              let workspaceURL = identity.url.flatMap(slackHTTPSURL),
              var url = URLComponents(url: workspaceURL, resolvingAgainstBaseURL: false) else {
            throw SlackSessionError.invalidResponse
        }
        url.path = "/"
        url.query = nil
        url.fragment = nil
        let info = try await request(UserInfo.self, team: team, in: store, method: "users.info",
                                     params: ["user": user.rawValue])
        guard info.ok, let profile = info.user?.profile, let canonicalURL = url.url else {
            throw SlackSessionError.invalidResponse
        }
        let userName = [profile.displayName, profile.realName].compactMap { $0 }.first { !$0.isEmpty }
        return AccountRecord.Team(id: id, name: name, url: canonicalURL, user: user, userName: userName ?? user.rawValue)
    }

    private static func request<T: Decodable>(_ type: T.Type, team: LocalConfig.Team, in store: WKWebsiteDataStore,
                                               method: String, params: [String: String] = [:]) async throws -> T {
        let response = try await nativePost(team, in: store, method: method, params: params)
        guard (200..<300).contains(response.status) else { throw SlackSessionError.invalidResponse }
        return try JSONDecoder().decode(type, from: response.body)
    }
}
