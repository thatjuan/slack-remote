import Darwin
import Foundation

/// Sends the passed file descriptor to Slack's upload URL from the helper.
public typealias FileUpload = @Sendable (_ team: TeamID, _ user: UserID, _ url: URL, _ file: FileHandle,
                                         _ size: Int64, _ deadline: Date) async throws -> Void

/// Shares an open file with a conversation or a verified thread.
public struct UploadRequest: RemoteOperation, Equatable {
    public static let defaultMaxSize: Int64 = 50_000_000
    public static let maximumMaxSize: Int64 = 1_000_000_000

    public struct Receipt: Encodable, Sendable {
        public let team: TeamID
        public let conversation: ConversationID
        public let thread: String?
        public let fileId: String
        public let fileName: String
        public let size: Int64
        public let ts: String?

        private enum CodingKeys: String, CodingKey {
            case team, conversation, thread, fileId, fileName, size, ts
        }

        public func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(team, forKey: .team)
            try fields.encode(conversation, forKey: .conversation)
            try fields.encode(thread, forKey: .thread)
            try fields.encode(fileId, forKey: .fileId)
            try fields.encode(fileName, forKey: .fileName)
            try fields.encode(size, forKey: .size)
            try fields.encode(ts, forKey: .ts)
        }
    }

    private struct UploadSlot: Decodable {
        let uploadUrl: URL
        let fileId: String
    }

    private struct UploadedFile: Encodable {
        let id: String
        let title: String
    }

    private struct FileInfo: Decodable {
        struct Share: Decodable { let ts: String? }

        struct Shares: Decodable {
            let `public`: [String: [Share]]?
            let `private`: [String: [Share]]?
        }

        struct File: Decodable { let shares: Shares? }

        let file: File
    }

    public let target: WriteTarget
    public let fileName: String
    public let maxSize: Int64
    public let text: String?
    public let thread: String?
    public let dryRun: Bool

    public init(target: WriteTarget, fileName: String, maxSize: Int64 = defaultMaxSize, text: String? = nil,
                thread: String? = nil, dryRun: Bool = false) {
        self.target = target
        self.fileName = fileName
        self.maxSize = maxSize
        self.text = text
        self.thread = thread
        self.dryRun = dryRun
    }

    public func run(in context: OperationContext) async throws -> WriteResult<Receipt> {
        let preflight = try await WritePreflight(target, in: context)
        guard let file = context.file else { throw RemoteError.fileRejected(reason: "unreadable") }
        let size = try validateFile(file)
        if let text { try MessageText.validate(text, allowBroadcast: false) }
        if let thread, !SlackTimestamp.isValid(thread) { throw RemoteError.messageNotFound }
        let name = try await preflight.verifyConversation(thread: thread)
        if dryRun {
            let plan = "upload \(fileName) (\(size) bytes)"
            return .dryRun(try await preflight.preview(plan, conversationName: name, in: context))
        }

        guard let upload = context.upload else { throw RemoteError.sessionUnavailable }
        let api = preflight.api
        let conversation = preflight.destination.conversation
        let slot = try await api.call("files.getUploadURLExternal", ["filename": fileName, "length": String(size)],
                                      as: UploadSlot.self)
        try await upload(api.team, api.user, slot.uploadUrl, file, size, context.deadline)

        let files = try JSONEncoder().encode([UploadedFile(id: slot.fileId, title: fileName)])
        var params = ["files": String(decoding: files, as: UTF8.self), "channel_id": conversation.rawValue]
        params["thread_ts"] = thread
        params["initial_comment"] = text
        do { _ = try await api.call("files.completeUploadExternal", params, as: SlackAcknowledgement.self) }
        catch RemoteError.networkUnavailable { throw RemoteError.uploadUnconfirmed }

        let ts = try await shareTimestamp(slot.fileId, in: conversation, api: api, deadline: context.deadline)
        if ts == nil { context.warn("share_pending") }
        return .completed(.init(team: api.team, conversation: conversation, thread: thread, fileId: slot.fileId,
                                fileName: fileName, size: size, ts: ts))
    }

    /// Checks the exact descriptor received over the socket.
    private func validateFile(_ file: FileHandle) throws -> Int64 {
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0 else { throw RemoteError.fileRejected(reason: "unreadable") }
        guard info.st_mode & S_IFMT == S_IFREG else { throw RemoteError.fileRejected(reason: "not_regular") }
        guard info.st_size > 0 else { throw RemoteError.fileRejected(reason: "empty") }
        guard info.st_size <= maxSize, info.st_size <= Self.maximumMaxSize else {
            throw RemoteError.fileRejected(reason: "too_large")
        }
        try FileName.validate(fileName)
        return info.st_size
    }

    /// Bounds the optional receipt lookup even when a request or rate-limit wait is slow.
    private func shareTimestamp(_ fileId: String, in conversation: ConversationID, api: SlackAPI,
                                deadline: Date) async throws -> String? {
        let interval = min(5, deadline.timeIntervalSinceNow)
        guard interval > 0 else { return nil }
        let stop = ContinuousClock.now + .seconds(interval)
        return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                while ContinuousClock.now < stop {
                    do {
                        let info = try await api.call("files.info", ["file": fileId], as: FileInfo.self)
                        let channel = conversation.rawValue
                        if let ts = info.file.shares?.public?[channel]?.first?.ts ??
                            info.file.shares?.private?[channel]?.first?.ts {
                            return ts
                        }
                    } catch RemoteError.interrupted {
                        throw RemoteError.interrupted
                    } catch RemoteError.timeout {
                        return nil
                    } catch {
                        // Completion already succeeded. Slack may still be indexing the share.
                    }
                    try await Task.sleep(until: min(stop, ContinuousClock.now + .milliseconds(500)), clock: .continuous)
                }
                return nil
            }
            group.addTask {
                try await Task.sleep(until: stop, clock: .continuous)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}
