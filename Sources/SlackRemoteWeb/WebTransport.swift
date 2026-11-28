import Foundation
import SlackRemoteCore

/// Uses the account's browser profile to authorize native Slack API requests.
@MainActor
public struct WebTransport: SlackTransport {
    private let pool: SessionPool
    private let accountID: AccountID

    public init(pool: SessionPool, accountID: AccountID) {
        self.pool = pool
        self.accountID = accountID
    }

    public func post(team: TeamID, method: String, params: [String: String]) async throws -> TransportResponse {
        let (_, session) = try resolve(team)
        let config: LocalConfig.Team
        do {
            config = try await session.credentials(for: team)
        } catch {
            try Task.checkCancellation()
            throw TransportFailure.notSent
        }
        let (workspace, current) = try resolve(team)
        guard current === session, let store = session.dataStore else { throw TransportFailure.notSent }
        guard config.id == team.rawValue, config.userID == workspace.user.rawValue else {
            throw RemoteError.accountMismatch
        }
        return try await nativePost(config, in: store, method: method, params: params)
    }

    /// Supplies the team's scoped cookies if Slack requires them for the external upload.
    public func uploadCookies(for team: TeamID, to url: URL) async throws -> [HTTPCookie] {
        do {
            let (_, session) = try resolve(team)
            guard let store = session.dataStore else { throw RemoteError.sessionUnavailable }
            guard let url = slackHTTPSURL(url.absoluteString), let host = url.host?.lowercased() else { return [] }
            let cookies = await slackCookies(in: store, for: url, host: host)
            let (_, current) = try resolve(team)
            guard current === session else { throw RemoteError.sessionUnavailable }
            return cookies
        } catch TransportFailure.notSent {
            throw RemoteError.sessionUnavailable
        }
    }

    /// Reload the client's document so Slack can recover the team's session.
    public func refresh(for team: TeamID) async -> Bool {
        guard let (_, session) = try? resolve(team) else { return false }
        return await session.refresh(for: team) != nil
    }

    /// Record that this profile needs manual sign-in after refresh failed.
    public func markSignedOut(team: TeamID) throws {
        guard let (record, _) = pool.session(for: team), record.id == accountID, record.state == .active else { return }
        var next = record
        next.state = .signedOut
        do { try pool.update(next) }
        catch { throw RemoteError.internalError(operation: "save_account") }
    }

    private func resolve(_ team: TeamID) throws -> (AccountRecord.Team, SlackSession) {
        guard let (record, session) = pool.session(for: team), record.id == accountID,
              let workspace = record.teams.first(where: { $0.id == team }) else {
            throw TransportFailure.notSent
        }
        guard record.state == .active else { throw RemoteError.accountSignedOut(team: workspace.name) }
        return (workspace, session)
    }
}
