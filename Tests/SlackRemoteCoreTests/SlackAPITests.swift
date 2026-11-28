import Foundation
@testable import SlackRemoteCore
import Testing

struct SlackAPITests {
    private static let team = TeamID("T00000001")!
    private static let user = UserID("U00000001")!

    private struct TestResponse: Decodable {
        let userId: UserID
    }

    private struct TestPage: CursorPage {
        struct Metadata: Decodable { let nextCursor: String? }
        let items: [Int]
        let responseMetadata: Metadata?
        var nextCursor: String? { responseMetadata?.nextCursor }
    }

    private actor StubTransport: SlackTransport {
        struct Request: Equatable {
            let team: TeamID
            let method: String
            let params: [String: String]
        }

        private var responses: [Result<TransportResponse, TransportFailure>]
        private(set) var requests: [Request] = []

        init(_ responses: [Result<TransportResponse, TransportFailure>]) {
            self.responses = responses
        }

        func post(team: TeamID, method: String, params: [String: String]) throws -> TransportResponse {
            requests.append(Request(team: team, method: method, params: params))
            guard !responses.isEmpty else { throw TransportFailure.notSent }
            return try responses.removeFirst().get()
        }
    }

    private actor Recovery {
        private(set) var refreshes = 0
        private(set) var state = AccountRecord.State.active

        func refresh() -> Bool {
            refreshes += 1
            return true
        }

        func markSignedOut() { state = .signedOut }
    }

    private static func response(_ json: String, status: Int = 200, retryAfter: Double? = nil)
        -> Result<TransportResponse, TransportFailure> {
        .success(TransportResponse(status: status, retryAfter: retryAfter, body: Data(json.utf8)))
    }

    private func api(using transport: StubTransport, seconds: Double = 10) -> SlackAPI {
        SlackAPI(team: Self.team, user: Self.user, transport: transport, deadline: Date().addingTimeInterval(seconds))
    }

    @Test func decodesSnakeCaseAndSendsTeamAndParams() async throws {
        let transport = StubTransport([Self.response(#"{"ok":true,"user_id":"U00000001"}"#)])
        let result = try await api(using: transport).call("auth.test", ["check": "yes"], as: TestResponse.self)
        #expect(result.userId == Self.user)
        #expect(await transport.requests == [.init(team: Self.team, method: "auth.test", params: ["check": "yes"])])
    }

    @Test(arguments: [
        ("invalid_auth", RemoteError.sessionExpired),
        ("not_authed", .sessionExpired),
        ("token_revoked", .sessionExpired),
        ("token_expired", .sessionExpired),
        ("account_inactive", .sessionExpired),
        ("channel_not_found", .destinationUnreachable),
        ("not_in_channel", .destinationUnreachable),
        ("thread_not_found", .messageNotFound),
        ("message_not_found", .messageNotFound),
        ("invalid_arguments", .slackAPI(method: "auth.test", error: "invalid_arguments")),
    ])
    func mapsSlackErrors(_ code: String, _ expected: RemoteError) async {
        let transport = StubTransport([Self.response(#"{"ok":false,"error":"\#(code)"}"#)])
        await #expect(throws: expected) { try await api(using: transport).call("auth.test", as: TestResponse.self) }
        #expect(await transport.requests.count == 1)
    }

    @Test func mapsNon2xxEvenWhenBodyIsNotJSON() async {
        let transport = StubTransport([Self.response("Unreachable", status: 502)])
        await #expect(throws: RemoteError.slackAPI(method: "auth.test", error: "http_502")) {
            try await api(using: transport).call("auth.test", as: TestResponse.self)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [429, 200])
    func retriesRateLimitedRequests(_ status: Int) async throws {
        let transport = StubTransport([
            Self.response(status == 429 ? "" : #"{"ok":false,"error":"ratelimited"}"#, status: status, retryAfter: 0.01),
            Self.response(#"{"ok":true,"user_id":"U00000001"}"#),
        ])
        let result = try await api(using: transport).call("auth.test", as: TestResponse.self)
        #expect(result.userId == Self.user)
        let requests = await transport.requests
        #expect(requests.count == 2 && requests.first == requests.last)
    }

    @Test func rateLimitPastDeadlineIsNotRetried() async {
        let transport = StubTransport([Self.response("", status: 429, retryAfter: 30)])
        await #expect(throws: RemoteError.rateLimited(retryAfter: 30)) {
            try await api(using: transport).call("auth.test", as: TestResponse.self)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: [(TransportFailure.notSent, RemoteError.sessionUnavailable), (.noResponse, .networkUnavailable)])
    func tellsTransportFailuresApart(_ failure: TransportFailure, _ expected: RemoteError) async {
        let transport = StubTransport([.failure(failure)])
        await #expect(throws: expected) { try await api(using: transport).call("auth.test", as: TestResponse.self) }
        #expect(await transport.requests.count == 1)
    }

    @Test(arguments: ["second-cursor", ""])
    func pagesUntilLimitOrEmptyCursor(_ lastCursor: String) async throws {
        let transport = StubTransport([
            Self.response(#"{"ok":true,"items":[1,2],"response_metadata":{"next_cursor":"first-cursor"}}"#),
            Self.response(#"{"ok":true,"items":[3],"response_metadata":{"next_cursor":"\#(lastCursor)"}}"#),
        ])
        let result = try await api(using: transport).paginate("items.list", ["scope": "mine"], limit: 3, perPage: 2,
                                                             as: TestPage.self)
        #expect(result.items == [1, 2, 3])
        #expect(result.pages == 2)
        #expect(result.complete == lastCursor.isEmpty)
        #expect(result.stopReason == (lastCursor.isEmpty ? .endOfList : .limit))
        #expect(await transport.requests.map(\.params) == [
            ["scope": "mine", "limit": "2"],
            ["scope": "mine", "limit": "1", "cursor": "first-cursor"],
        ])
    }

    @Test func stopsPagingAtDeadline() async throws {
        let transport = StubTransport([])
        let result = try await api(using: transport, seconds: -1).paginate("items.list", [:], limit: 3, as: TestPage.self)
        #expect(result.items.isEmpty)
        #expect(result.pages == 0)
        #expect(!result.complete)
        #expect(result.stopReason == .deadline)
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func refreshesOnceAfterAnExpiredSession(_ recovered: Bool) async throws {
        let expired = Self.response(#"{"ok":false,"error":"token_expired"}"#)
        let transport = StubTransport([
            expired,
            Self.response("", status: 429, retryAfter: 0),
            recovered ? Self.response(#"{"ok":true,"user_id":"U00000001"}"#) : expired,
        ])
        let recovery = Recovery()
        let deadline = Date().addingTimeInterval(10)
        let api = SlackAPI(team: Self.team, user: Self.user, deadline: deadline, makeTransport: {
            SessionRefreshingTransport(base: transport, teamName: "Acme", deadline: deadline,
                                       refresh: { await recovery.refresh() }, signOut: { await recovery.markSignedOut() })
        })

        if recovered {
            let result = try await api.call("auth.test", as: TestResponse.self)
            #expect(result.userId == Self.user)
        } else {
            await #expect(throws: RemoteError.accountSignedOut(team: "Acme")) {
                try await api.call("auth.test", as: TestResponse.self)
            }
        }
        #expect(await transport.requests.count == 3)
        #expect(await recovery.refreshes == 1)
        #expect(await recovery.state == (recovered ? .active : .signedOut))
    }
}
