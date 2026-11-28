import Darwin
import Foundation
import os
@testable import SlackRemoteCore
import Testing

struct WriteTests {
    private static let team = TeamID("T00000001")!
    private static let user = UserID("U00000001")!
    private static let channel = ConversationID("C00000001")!
    private static let destination = Destination(team: team, conversation: channel)
    private let target = WriteTarget.named("fixture")
    private let root = "1700000400.000100"
    private let reply = "1700000400.000200"
    private let text = "fixture"
    private let info = #"{"ok":true,"channel":{"name":"fixture","is_channel":true,"is_member":true}}"#

    private actor StubTransport: SlackTransport {
        private var responses: [Result<TransportResponse, TransportFailure>]
        private(set) var calls: [(method: String, params: [String: String])] = []

        init(_ responses: [Result<TransportResponse, TransportFailure>]) { self.responses = responses }

        func post(team: TeamID, method: String, params: [String: String]) throws -> TransportResponse {
            calls.append((method, params))
            guard !responses.isEmpty else { throw TransportFailure.notSent }
            return try responses.removeFirst().get()
        }
    }

    private func response(_ json: String, status: Int = 200, retryAfter: Double? = nil)
        -> Result<TransportResponse, TransportFailure> {
        .success(.init(status: status, retryAfter: retryAfter, body: Data(json.utf8)))
    }

    private func rootInfo() -> Result<TransportResponse, TransportFailure> {
        response(#"{"ok":true,"messages":[{"ts":"\#(root)","thread_ts":"\#(root)"}]}"#)
    }

    private func context(
        _ transport: StubTransport, unavailable: Bool = false, file: FileHandle? = nil,
        allowed: Bool = true, timeout: Double = 10, upload: FileUpload? = nil,
        warn: @escaping @Sendable (String) -> Void = { _ in }
    ) -> OperationContext {
        var settings = Config()
        settings.destinations["fixture"] = Self.destination
        settings.restrictWritesToDestinations = true
        if !allowed {
            settings.destinations["fixture"] = nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        let record = AccountRecord(id: AccountID(), teams: [
            .init(id: Self.team, name: "Acme", url: URL(string: "https://acme.slack.com")!,
                  user: Self.user, userName: "Ada"),
        ], state: .active, addedAt: Date())
        return OperationContext(deadline: deadline, config: settings, file: file, upload: upload,
                                helperVersion: "2.0.0", accounts: { [record] }, api: { team in
            #expect(team == Self.team)
            if unavailable { throw RemoteError.noAccount(team: team) }
            return SlackAPI(team: Self.team, user: Self.user, transport: transport, deadline: deadline)
        }, ui: AccountUI(add: { _, _ in nil }, remove: { _ in }), warn: warn)
    }

    @Test func resolvesAccountBeforeAllowlistAndValidatesBeforeContactingSlack() async {
        let transport = StubTransport([])
        let request = SendRequest(target: .explicit(Self.destination), text: "/x", dryRun: true)
        await #expect(throws: RemoteError.noAccount(team: Self.team)) {
            try await request.run(in: context(transport, unavailable: true, allowed: false))
        }
        await #expect(throws: RemoteError.writeNotAllowed) {
            try await request.run(in: context(transport, allowed: false))
        }
        await #expect(throws: RemoteError.unsafeText(reason: "slash_command")) {
            try await request.run(in: context(transport))
        }
        #expect(await transport.calls.isEmpty)
    }

    @Test func dryRunsStopAfterConversationAndThreadChecks() async throws {
        let transport = StubTransport([response(info), response(info), rootInfo(), response(info),
                                       response(info), rootInfo()])
        let send = try await SendRequest(target: target, text: text, dryRun: true).run(in: context(transport))
        guard case .dryRun(let message) = send else { Issue.record("Expected a send plan"); return }
        #expect(message.plan == ["post message (7 characters)"])
        #expect(message.account.user == Self.user && message.account.userName == "Ada")
        #expect(message.conversationName == "fixture")

        let reply = try await ReplyRequest(target: target, thread: root, text: text, alsoSendToChannel: true,
                                           dryRun: true).run(in: context(transport))
        guard case .dryRun(let thread) = reply else { Issue.record("Expected a reply plan"); return }
        #expect(thread.plan == ["post reply in thread \(root) (7 characters), also to channel"])

        let reacts = try await ReactRequest(target: target, ts: root, emoji: "+1", dryRun: true)
            .run(in: context(transport))
        guard case .dryRun(let reaction) = reacts else { Issue.record("Expected a reaction plan"); return }
        #expect(reaction.plan == ["add reaction :+1: to \(root)"])

        try await withFile(Data("file".utf8)) { file in
            let upload = try await UploadRequest(target: target, fileName: "file.txt", thread: root, dryRun: true)
                .run(in: context(transport, file: file))
            guard case .dryRun(let plan) = upload else { Issue.record("Expected an upload plan"); return }
            #expect(plan.plan == ["upload file.txt (4 bytes)"])
        }
        let calls = await transport.calls
        #expect(calls.map(\.method) == ["conversations.info", "conversations.info", "conversations.replies",
                                       "conversations.info", "conversations.info", "conversations.replies"])
        #expect(calls[2].params == ["channel": Self.channel.rawValue, "ts": root, "limit": "1"])
        #expect(calls[5].params == calls[2].params)
    }

    @Test(arguments: [
        (#"{"ok":true,"channel":{"is_group":true,"is_member":false}}"#, RemoteError.destinationUnavailable(reason: .notAMember)),
        (#"{"ok":true,"channel":{"is_archived":true}}"#, .destinationUnavailable(reason: .archived)),
        (#"{"ok":false,"error":"channel_not_found"}"#, .destinationUnreachable),
    ])
    func refusesUnreachableConversations(_ json: String, _ error: RemoteError) async {
        let transport = StubTransport([response(json)])
        await #expect(throws: error) {
            try await ReplyRequest(target: target, thread: root, text: text).run(in: context(transport))
        }
        #expect(await transport.calls.map(\.method) == ["conversations.info"])
    }

    @Test func rejectsReplyTimestampAndUnknownThreadBeforePosting() async {
        let child = response(#"{"ok":true,"messages":[{"ts":"\#(reply)","thread_ts":"\#(root)"}]}"#)
        let wrongRoot = response(#"{"ok":true,"messages":[{"ts":"\#(root)"}]}"#)
        let missing = response(#"{"ok":false,"error":"thread_not_found"}"#)
        for response in [child, wrongRoot, missing] {
            let transport = StubTransport([self.response(info), response])
            let request = ReplyRequest(target: target, thread: reply, text: text)
            await #expect(throws: RemoteError.messageNotFound) { try await request.run(in: context(transport)) }
            #expect(await transport.calls.map(\.method) == ["conversations.info", "conversations.replies"])
        }
    }

    @Test(arguments: [false, true])
    func postsReplyWithExplicitBroadcastSetting(_ broadcast: Bool) async throws {
        let transport = StubTransport([response(info), rootInfo(), response(#"{"ok":true,"ts":"\#(reply)"}"#)])
        let result = try await ReplyRequest(target: target, thread: root, text: text, alsoSendToChannel: broadcast)
            .run(in: context(transport))
        guard case .completed(let receipt) = result else { Issue.record("Expected a reply receipt"); return }
        #expect(receipt.ts == reply && receipt.thread == root)
        let post = try #require(await transport.calls.last)
        #expect(post.method == "chat.postMessage")
        #expect(post.params == ["channel": Self.channel.rawValue, "text": text, "thread_ts": root,
                                "reply_broadcast": String(broadcast)])
    }

    @Test func confirmsExistingReactionAndAddressesMessageDirectly() async throws {
        let transport = StubTransport([response(info), response(#"{"ok":false,"error":"already_reacted"}"#)])
        let result = try await ReactRequest(target: target, ts: reply, emoji: "tada").run(in: context(transport))
        guard case .completed(let receipt) = result else { Issue.record("Expected a reaction receipt"); return }
        #expect(receipt.reacted && receipt.alreadyReacted)
        let calls = await transport.calls
        #expect(calls.map(\.method) == ["conversations.info", "reactions.add"])
        #expect(calls[1].params == ["channel": Self.channel.rawValue, "timestamp": reply, "name": "tada"])
    }

    @Test(arguments: [
        ("invalid_name", RemoteError.unsafeText(reason: "invalid_emoji_name")),
        ("message_not_found", .messageNotFound),
    ])
    func mapsSlackReactionRejections(_ code: String, _ expected: RemoteError) async {
        let transport = StubTransport([response(info), response(#"{"ok":false,"error":"\#(code)"}"#)])
        await #expect(throws: expected) {
            try await ReactRequest(target: target, ts: root, emoji: "tada").run(in: context(transport))
        }
    }

    @Test func noResponseFromPostIsUnconfirmedAndIsNeverRetried() async {
        let request = SendRequest(target: target, text: text)
        let preflight = StubTransport([.failure(.noResponse)])
        await #expect(throws: RemoteError.networkUnavailable) { try await request.run(in: context(preflight)) }
        let write = StubTransport([response(info), .failure(.noResponse), response(#"{"ok":true,"ts":"\#(root)"}"#)])
        await #expect(throws: RemoteError.sendUnconfirmed) { try await request.run(in: context(write)) }
        #expect(await write.calls.map(\.method) == ["conversations.info", "chat.postMessage"])
    }

    @Test func retriesRejectedRateLimitedPostAndReturnsSlackTimestamp() async throws {
        let transport = StubTransport([response(info), response("", status: 429, retryAfter: 0),
                                       response(#"{"ok":true,"ts":"\#(root)"}"#)])
        let result = try await SendRequest(target: target, text: text).run(in: context(transport))
        guard case .completed(let receipt) = result else { Issue.record("Expected a send receipt"); return }
        #expect(receipt.ts == root)
        let calls = await transport.calls
        #expect(calls.map(\.method) == ["conversations.info", "chat.postMessage", "chat.postMessage"])
        #expect(calls[1].params == calls[2].params)
    }

    @Test(arguments: [(0, "file.txt", "empty"), (2, "file.txt", "too_large"), (1, ".file", "invalid_name")])
    func rejectsInvalidFilesBeforeCallingSlack(_ size: Int, _ name: String, _ reason: String) async throws {
        try await withFile(Data(repeating: 0, count: size)) { file in
            let transport = StubTransport([])
            let request = UploadRequest(target: target, fileName: name, maxSize: 1)
            await #expect(throws: RemoteError.fileRejected(reason: reason)) {
                try await request.run(in: context(transport, file: file))
            }
            #expect(await transport.calls.isEmpty)
        }
    }

    @Test func rejectsDirectoryDescriptor() async throws {
        let descriptor = open(FileManager.default.temporaryDirectory.path, O_RDONLY | O_DIRECTORY)
        try #require(descriptor >= 0)
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let transport = StubTransport([])
        let request = UploadRequest(target: target, fileName: "directory")
        await #expect(throws: RemoteError.fileRejected(reason: "not_regular")) {
            try await request.run(in: context(transport, file: handle))
        }
        #expect(await transport.calls.isEmpty)
    }

    @Test func passesCompletionParamsAndReturnsTheShareTimestamp() async throws {
        try await withFile(Data("file".utf8)) { file in
            let slot = response(#"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/example","file_id":"F001"}"#)
            let share = response(#"{"ok":true,"file":{"shares":{"private":{"\#(Self.channel.rawValue)":[{"ts":"\#(reply)"}]}}}}"#)
            let transport = StubTransport([response(info), rootInfo(), slot, response(#"{"ok":true}"#), share])
            let request = UploadRequest(target: target, fileName: "file.txt", text: text, thread: root)
            let result = try await request.run(in: context(transport, file: file, upload: { team, user, url, handle, size, _ in
                #expect(await transport.calls.map(\.method) == ["conversations.info", "conversations.replies",
                                                               "files.getUploadURLExternal"])
                #expect(team == Self.team && user == Self.user)
                #expect(url.host == "files.slack.com" && handle === file && size == 4)
            }))
            guard case .completed(let receipt) = result else { Issue.record("Expected an upload receipt"); return }
            #expect(receipt.fileId == "F001" && receipt.thread == root && receipt.ts == reply)
            let calls = await transport.calls
            #expect(calls[2].params == ["filename": "file.txt", "length": "4"])
            let complete = calls[3]
            #expect(complete.method == "files.completeUploadExternal")
            #expect(complete.params["channel_id"] == Self.channel.rawValue)
            #expect(complete.params["thread_ts"] == root)
            #expect(complete.params["initial_comment"] == text)
            let files = try #require(complete.params["files"])
            #expect(try JSONDecoder().decode([[String: String]].self, from: Data(files.utf8)) ==
                    [["id": "F001", "title": "file.txt"]])
        }
    }

    @Test func completedUploadWithNoShareReturnsNullAndWarning() async throws {
        try await withFile(Data("file".utf8)) { file in
            let slot = response(#"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/example","file_id":"F001"}"#)
            let transport = StubTransport([response(info), slot, response(#"{"ok":true}"#),
                                           response(#"{"ok":true,"file":{}}"#), response(#"{"ok":true,"file":{}}"#)])
            let request = UploadRequest(target: target, fileName: "file.txt")
            let warnings = OSAllocatedUnfairLock(initialState: [String]())
            let result = try await request.run(in: context(transport, file: file, timeout: 0.8,
                upload: { _, _, _, _, _, _ in }, warn: { warning in warnings.withLock { $0.append(warning) } }))
            guard case .completed(let receipt) = result else { Issue.record("Expected an upload receipt"); return }
            #expect(receipt.ts == nil)
            let json = try String(decoding: JSONEncoder().encode(receipt), as: UTF8.self)
            #expect(json.contains(#""ts":null"#))
            #expect(warnings.withLock { $0 } == ["share_pending"])
            #expect(await transport.calls.map(\.method).contains("files.info"))
        }
    }

    @Test func lostUploadCompletionResponseIsUnconfirmedWithoutRetrying() async throws {
        try await withFile(Data("file".utf8)) { file in
            let slot = response(#"{"ok":true,"upload_url":"https://files.slack.com/upload/v1/example","file_id":"F001"}"#)
            let request = UploadRequest(target: target, fileName: "file.txt")
            let prepare = StubTransport([response(info), .failure(.noResponse)])
            await #expect(throws: RemoteError.networkUnavailable) {
                try await request.run(in: context(prepare, file: file, upload: { _, _, _, _, _, _ in
                    Issue.record("Prepared no upload slot")
                }))
            }
            let complete = StubTransport([response(info), slot, .failure(.noResponse)])
            await #expect(throws: RemoteError.uploadUnconfirmed) {
                try await request.run(in: context(complete, file: file, upload: { _, _, _, _, _, _ in }))
            }
            #expect(await complete.calls.map(\.method) == [
                "conversations.info", "files.getUploadURLExternal", "files.completeUploadExternal",
            ])
        }
    }

    /// Creates a regular fixture and keeps its descriptor open for the operation.
    private func withFile(_ data: Data, _ run: (FileHandle) async throws -> Void) async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: path, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: path) }
        let file = try FileHandle(forReadingFrom: path)
        defer { try? file.close() }
        try await run(file)
    }
}
