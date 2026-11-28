import Foundation

/// An HTTP response from the workspace API endpoint.
public struct TransportResponse: Sendable {
    public let status: Int
    public let retryAfter: Double?
    public let body: Data

    public init(status: Int, retryAfter: Double? = nil, body: Data) {
        self.status = status
        self.retryAfter = retryAfter
        self.body = body
    }

    fileprivate var metadata: SlackResponse? { try? SlackAPI.decoder.decode(SlackResponse.self, from: body) }

    fileprivate var sessionExpired: Bool {
        guard (200..<300).contains(status), let metadata, metadata.ok == false, let error = metadata.error else {
            return false
        }
        return SlackResponse.expiredErrors.contains(error)
    }
}

private struct SlackResponse: Decodable {
    let ok: Bool?
    let error: String?

    static let expiredErrors: Set<String> =
        ["invalid_auth", "not_authed", "token_revoked", "token_expired", "account_inactive"]
}

public enum TransportFailure: Error, Sendable {
    /// The request never left the Mac.
    case notSent
    /// No response arrived. Slack may have applied the request.
    case noResponse
}

/// POSTs form-encoded params with the team's session credentials.
public protocol SlackTransport: Sendable {
    func post(team: TeamID, method: String, params: [String: String]) async throws -> TransportResponse
}

public protocol CursorPage: Decodable {
    associatedtype Item: Decodable & Sendable
    var items: [Item] { get }
    var nextCursor: String? { get }
}

public struct Paged<Item: Sendable>: Sendable {
    public let items: [Item]
    public let stopReason: StopReason
    public let pages: Int

    public var complete: Bool { stopReason == .endOfList }
}

/// A Slack API client bound to a workspace, its signed-in user and the command deadline.
public struct SlackAPI: Sendable {
    public let team: TeamID
    public let user: UserID
    private let deadline: Date
    private let makeTransport: @Sendable () -> any SlackTransport

    public init(team: TeamID, user: UserID, transport: any SlackTransport, deadline: Date) {
        self.init(team: team, user: user, deadline: deadline, makeTransport: { transport })
    }

    /// Give each API call its own transport state across retries.
    public init(team: TeamID, user: UserID, deadline: Date,
                makeTransport: @escaping @Sendable () -> any SlackTransport) {
        self.team = team
        self.user = user
        self.deadline = deadline
        self.makeTransport = makeTransport
    }

    fileprivate static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public func call<Response: Decodable>(_ method: String, _ params: [String: String] = [:],
                                         as: Response.Type = Response.self) async throws -> Response {
        let transport = makeTransport()
        while true {
            guard !Task.isCancelled else { throw RemoteError.interrupted }
            guard Date() < deadline else { throw RemoteError.timeout }

            let response: TransportResponse
            do {
                response = try await transport.post(team: team, method: method, params: params)
            } catch {
                if Task.isCancelled || error is CancellationError { throw RemoteError.interrupted }
                switch error as? TransportFailure {
                case .notSent: throw RemoteError.sessionUnavailable
                case .noResponse: throw RemoteError.networkUnavailable
                case nil: throw error
                }
            }
            guard !Task.isCancelled else { throw RemoteError.interrupted }
            let metadata = response.metadata
            if response.status == 429 || metadata?.error == "ratelimited" {
                try await waitForRateLimit(response.retryAfter)
                continue
            }
            guard (200..<300).contains(response.status) else {
                throw RemoteError.slackAPI(method: method, error: "http_\(response.status)")
            }
            switch metadata?.ok {
            case true?:
                do { return try Self.decoder.decode(Response.self, from: response.body) }
                catch { throw RemoteError.slackAPI(method: method, error: "invalid_response") }
            case false?:
                throw Self.slackError(method: method, code: metadata?.error ?? "unknown_error")
            case nil:
                throw RemoteError.slackAPI(method: method, error: "invalid_response")
            }
        }
    }

    private func waitForRateLimit(_ header: Double?) async throws {
        let delay = header.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 1
        guard delay < deadline.timeIntervalSinceNow else { throw RemoteError.rateLimited(retryAfter: delay) }
        do { try await Task.sleep(for: .seconds(delay)) }
        catch { throw RemoteError.interrupted }
        guard Date() < deadline else { throw RemoteError.rateLimited(retryAfter: delay) }
    }

    private static func slackError(method: String, code: String) -> RemoteError {
        switch code {
        case let code where SlackResponse.expiredErrors.contains(code): return .sessionExpired
        case "channel_not_found", "not_in_channel": return .destinationUnreachable
        case "thread_not_found", "message_not_found": return .messageNotFound
        default: return .slackAPI(method: method, error: code)
        }
    }

    /// Fetch only the pages needed to fill the requested limit.
    public func paginate<Page: CursorPage>(_ method: String, _ params: [String: String], limit: Int,
                                           perPage: Int = 200, as: Page.Type,
                                           collect: ([Page.Item], Int) async throws -> [Page.Item] = { items, _ in items }
    ) async throws -> Paged<Page.Item> {
        var items: [Page.Item] = []
        var cursor: String?
        var pages = 0
        var params = params
        while items.count < limit {
            guard !Task.isCancelled else { throw RemoteError.interrupted }
            guard Date() < deadline else { return Paged(items: items, stopReason: .deadline, pages: pages) }
            params["limit"] = String(min(max(1, perPage), limit - items.count))
            params["cursor"] = cursor
            let page: Page
            do { page = try await call(method, params, as: Page.self) }
            catch RemoteError.timeout { return Paged(items: items, stopReason: .deadline, pages: pages) }
            pages += 1
            let collected = try await collect(page.items, pages)
            let remaining = limit - items.count
            items.append(contentsOf: collected.prefix(remaining))
            if collected.count > remaining { return Paged(items: items, stopReason: .limit, pages: pages) }
            guard let next = page.nextCursor, !next.isEmpty else {
                return Paged(items: items, stopReason: .endOfList, pages: pages)
            }
            cursor = next
        }
        return Paged(items: items, stopReason: .limit, pages: pages)
    }
}

/// Recovers an expired session once across the attempts for a single API call.
public actor SessionRefreshingTransport: SlackTransport {
    private let base: any SlackTransport
    private let teamName: String
    private let deadline: Date
    private let refresh: @Sendable () async -> Bool
    private let signOut: @Sendable () async throws -> Void
    private var refreshed = false

    public init(base: any SlackTransport, teamName: String, deadline: Date,
                refresh: @escaping @Sendable () async -> Bool,
                signOut: @escaping @Sendable () async throws -> Void) {
        self.base = base
        self.teamName = teamName
        self.deadline = deadline
        self.refresh = refresh
        self.signOut = signOut
    }

    public func post(team: TeamID, method: String, params: [String: String]) async throws -> TransportResponse {
        while true {
            let response = try await base.post(team: team, method: method, params: params)
            try Task.checkCancellation()
            guard response.sessionExpired else { return response }
            if !refreshed {
                refreshed = true
                guard Date() < deadline else { throw RemoteError.timeout }
                let recovered = await refresh()
                try Task.checkCancellation()
                guard Date() < deadline else { throw RemoteError.timeout }
                if recovered { continue }
            }
            try await signOut()
            throw RemoteError.accountSignedOut(team: teamName)
        }
    }
}
