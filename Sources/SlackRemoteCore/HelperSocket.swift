import Darwin
import Foundation

/// One reader per connection. Writers can share a connection without interleaving frames.
public final class HelperSocket: @unchecked Sendable {
    let descriptor: Int32
    private let writeLock = NSLock()
    private var input = Data()
    private var readBuffer = Data(count: 64 * 1024)

    private struct RightsMessage {
        // Darwin CMSG_LEN for one Int32: a 32-bit-aligned cmsghdr followed by the fd.
        static let length = socklen_t(MemoryLayout<Self>.size)
        var header = cmsghdr(cmsg_len: length, cmsg_level: SOL_SOCKET, cmsg_type: SCM_RIGHTS)
        var file: Int32 = -1
    }

    init(adopting descriptor: Int32) throws {
        var noSignal: Int32 = 1
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) != -1,
              setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                         socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0 else {
            throw Self.systemError()
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    static func systemError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func withAddress<T>(_ url: URL, _ work: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        let path = url.path.utf8CString
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            path.withUnsafeBytes { destination.copyBytes(from: $0) }
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                work($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    public static func connect(to url: URL) throws -> HelperSocket {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw systemError() }
        do {
            guard try withAddress(url, { Darwin.connect(fd, $0, $1) }) == 0 else { throw systemError() }
            return try HelperSocket(adopting: fd)
        } catch {
            close(fd)
            throw error
        }
    }

    public func disconnect() {
        shutdown(descriptor, SHUT_RDWR)
    }

    public func send(_ frame: HelperProtocol.Frame, passing file: Int32? = nil) throws {
        let data = HelperProtocol.encode(frame)
        try writeLock.withLock {
            try data.withUnsafeBytes { bytes in
                // The control message is sent once. A short write leaves ordinary frame bytes.
                let firstWrite = try file.map { try sendRights($0, with: bytes) } ?? 0
                var offset = firstWrite
                while offset < bytes.count {
                    let count = Darwin.send(descriptor, bytes.baseAddress?.advanced(by: offset),
                                            bytes.count - offset, 0)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw Self.systemError() }
                    offset += count
                }
            }
        }
    }

    private func sendRights(_ file: Int32, with bytes: UnsafeRawBufferPointer) throws -> Int {
        var rights = RightsMessage(file: file)
        var vector = iovec(iov_base: UnsafeMutableRawPointer(mutating: bytes.baseAddress), iov_len: bytes.count)
        let count = withUnsafeMutablePointer(to: &vector) { vector in
            withUnsafeMutablePointer(to: &rights) { rights in
                var message = msghdr()
                message.msg_iov = vector
                message.msg_iovlen = 1
                message.msg_control = UnsafeMutableRawPointer(rights)
                message.msg_controllen = RightsMessage.length
                var count: Int
                repeat { count = sendmsg(descriptor, &message, 0) } while count < 0 && errno == EINTR
                return count
            }
        }
        guard count > 0 else { throw Self.systemError() }
        return count
    }

    func receiveRequest() throws -> (HelperProtocol.Request, Int32?)? {
        var firstByte: UInt8 = 0
        var rights = RightsMessage()
        var message = msghdr()
        message.msg_iovlen = 1
        message.msg_controllen = RightsMessage.length
        let count = withUnsafeMutablePointer(to: &firstByte) { firstByte in
            var vector = iovec(iov_base: UnsafeMutableRawPointer(firstByte), iov_len: 1)
            return withUnsafeMutablePointer(to: &vector) { vector in
                withUnsafeMutablePointer(to: &rights) { rights in
                    message.msg_iov = vector
                    message.msg_control = UnsafeMutableRawPointer(rights)
                    var count: Int
                    repeat { count = recvmsg(descriptor, &message, 0) } while count < 0 && errno == EINTR
                    return count
                }
            }
        }
        guard count >= 0 else { throw Self.systemError() }
        guard count > 0 else { return nil }
        let file = message.msg_controllen >= RightsMessage.length && rights.header.cmsg_level == SOL_SOCKET
            && rights.header.cmsg_type == SCM_RIGHTS && rights.file >= 0 ? rights.file : nil

        do {
            guard message.msg_flags & MSG_CTRUNC == 0,
                  message.msg_controllen == 0 || (file != nil && rights.header.cmsg_len == RightsMessage.length)
            else { throw HelperProtocol.DecodeError.invalidPayload }
            if let file, fcntl(file, F_SETFD, FD_CLOEXEC) == -1 { throw Self.systemError() }
            input.append(firstByte)
            guard case .request(let request) = try receive(), request.passesFile == (file != nil) else {
                throw HelperProtocol.DecodeError.invalidPayload
            }
            return (request, file)
        } catch {
            if let file { close(file) }
            throw error
        }
    }

    public func receive() throws -> HelperProtocol.Frame? {
        while true {
            if let frame = try HelperProtocol.decode(from: &input) { return frame }
            let count = readBuffer.withUnsafeMutableBytes {
                recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw Self.systemError() }
            guard count > 0 else { return nil }
            input.append(readBuffer.prefix(count))
        }
    }
}
