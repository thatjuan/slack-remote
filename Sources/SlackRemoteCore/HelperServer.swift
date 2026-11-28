import Darwin
import Foundation
import os
import Security

/// Records the signal that interrupted a running helper call.
public final class CancellationSignal: Sendable {
    private let value = OSAllocatedUnfairLock<Int32?>(initialState: nil)
    public var signal: Int32? { value.withLock { $0 } }

    fileprivate func record(_ signal: Int32) { value.withLock { $0 = signal } }
}

public final class HelperServer: @unchecked Sendable {
    public typealias CallHandler = @Sendable (HelperProtocol.Call, FileHandle?, CancellationSignal) async -> Reply

    public struct Reply: Sendable {
        public let stdout: Data
        public let stderr: Data
        public let status: Int32

        public init(stdout: Data = Data(), stderr: Data = Data(), status: Int32) {
            self.stdout = stdout
            self.stderr = stderr
            self.status = status
        }
    }

    public struct LastCommand {
        public let name: String
        public let status: Int32
        public let time: Date
    }

    private let listener: DispatchSourceRead
    private let version: String
    private let callHandler: CallHandler
    private let peerRequirement: SecRequirement?
    private let lock = NSLock()
    private var last: LastCommand?

    public var lastCommand: LastCommand? { lock.withLock { last } }

    public init(socketURL: URL = HelperProtocol.socketURL,
                version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                callHandler: @escaping CallHandler)
        throws {
        self.version = version
        self.callHandler = callHandler
        peerRequirement = try Self.signingRequirement()

        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw HelperSocket.systemError() }
        do {
            var info = stat()
            guard fstat(directoryFD, &info) == 0 else { throw HelperSocket.systemError() }
            guard info.st_uid == getuid() else { throw POSIXError(.EACCES) }
            // Serialize stale-socket cleanup and hold the lock until this listener is closed.
            guard flock(directoryFD, LOCK_EX | LOCK_NB) == 0, fchmod(directoryFD, 0o700) == 0 else {
                throw HelperSocket.systemError()
            }
            let fd = try Self.listen(at: socketURL)
            listener = DispatchSource.makeReadSource(fileDescriptor: fd,
                                                     queue: DispatchQueue(label: "slack-remote.helper.accept"))
            listener.setCancelHandler {
                unlink(socketURL.path)
                close(fd)
                close(directoryFD)
            }
            listener.setEventHandler { [weak self] in self?.acceptConnection(fd) }
            listener.activate()
        } catch {
            close(directoryFD)
            throw error
        }
    }

    deinit { stop() }

    public func stop() {
        listener.cancel()
    }

    private static func listen(at url: URL) throws -> Int32 {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else { throw POSIXError(.EADDRINUSE) }
            do {
                _ = try HelperSocket.connect(to: url)
                throw POSIXError(.EADDRINUSE)
            } catch let error as POSIXError where error.code == .ECONNREFUSED {
                guard unlink(url.path) == 0 else { throw HelperSocket.systemError() }
            }
        } else if errno != ENOENT {
            throw HelperSocket.systemError()
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HelperSocket.systemError() }
        var bound = false
        do {
            guard fcntl(fd, F_SETFD, FD_CLOEXEC) != -1, fcntl(fd, F_SETFL, O_NONBLOCK) != -1,
                  try HelperSocket.withAddress(url, { bind(fd, $0, $1) }) == 0 else {
                throw HelperSocket.systemError()
            }
            bound = true
            guard chmod(url.path, 0o600) == 0, Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw HelperSocket.systemError()
            }
            return fd
        } catch {
            close(fd)
            if bound { unlink(url.path) }
            throw error
        }
    }

    private func acceptConnection(_ listenerFD: Int32) {
        let fd = accept(listenerFD, nil, nil)
        guard fd >= 0 else { return }
        guard fcntl(fd, F_SETFL, 0) != -1, let connection = try? HelperSocket(adopting: fd) else {
            close(fd)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serve(connection)
        }
    }

    private func serve(_ connection: HelperSocket) {
        defer { connection.disconnect() }
        guard isAuthorized(connection.descriptor) else {
            try? connection.send(.rejected("unauthorized"))
            return
        }
        do {
            guard let (call, descriptor) = try connection.receiveCall() else { return }
            let file = descriptor.map { FileHandle(fileDescriptor: $0, closeOnDealloc: true) }
            guard call.protocolVersion == HelperProtocol.version, call.clientVersion == version else {
                try connection.send(.rejected("version_mismatch"))
                return
            }

            let done = DispatchSemaphore(value: 0)
            let result = OSAllocatedUnfairLock<Reply?>(initialState: nil)
            let cancellation = CancellationSignal()
            let complete: @Sendable (Reply) -> Void = { reply in
                result.withLock { current in
                    guard current == nil else { return }
                    current = reply
                    done.signal()
                }
            }
            let task = Task {
                complete(await callHandler(call, file, cancellation))
            }
            DispatchQueue.global(qos: .userInitiated).async {
                // This queue owns reads after the initial call. Disconnecting unblocks it.
                defer { task.cancel() }
                while let frame = try? connection.receive() {
                    guard case .signal(let signal) = frame, [SIGINT, SIGTERM, SIGHUP].contains(signal) else { continue }
                    cancellation.record(signal)
                    let error = RemoteError.interrupted
                    let bytes = try? Envelope.failure(call.command, error: error, result: nil as Bool?)
                    complete(Reply(stderr: bytes ?? Data(), status: error.exitStatus))
                    break
                }
            }
            done.wait()
            guard let response = result.withLock({ $0 }) else { return }
            lock.withLock {
                last = LastCommand(name: call.command, status: response.status, time: Date())
            }
            try connection.send(.stdout(response.stdout))
            try connection.send(.stderr(response.stderr))
            try connection.send(.exit(response.status))
        } catch {}
    }

    private static func signingRequirement() throws -> SecRequirement? {
        var current: SecCode?
        var staticCode: SecStaticCode?
        var signingInfo: CFDictionary?
        guard SecCodeCopySelf([], &current) == errSecSuccess, let current,
              SecCodeCopyStaticCode(current, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &signingInfo) == errSecSuccess, let signingInfo else {
            throw POSIXError(.EACCES)
        }
        let team = (signingInfo as NSDictionary)[kSecCodeInfoTeamIdentifier] as? String
        guard let team else { return nil }
        guard !team.isEmpty, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
            throw POSIXError(.EACCES)
        }
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
              let requirement else { throw POSIXError(.EACCES) }
        return requirement
    }

    private func isAuthorized(_ socket: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(socket, &uid, &gid) == 0, uid == getuid() else { return false }
        guard let peerRequirement else { return true }

        var token = audit_token_t()
        var size = socklen_t(MemoryLayout.size(ofValue: token))
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout.size(ofValue: token) else { return false }
        let audit = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: audit] as CFDictionary
        var peer: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &peer) == errSecSuccess, let peer else {
            return false
        }
        return SecCodeCheckValidity(peer, [], peerRequirement) == errSecSuccess
    }
}
