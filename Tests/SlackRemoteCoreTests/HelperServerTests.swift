import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperServerTests {
    private static let version = "test-version"

    @Test func routesTypedCalls() throws {
        try withServer(callHandler: { call, _, _ in
            .init(stdout: Data(call.command.utf8), stderr: Data("test stderr".utf8), status: 3)
        }) { server, socket in
            try socket.send(.call(call()))
            let result = try readResult(socket)
            #expect(result.stdout == Data("accounts list".utf8))
            #expect(result.stderr == Data("test stderr".utf8))
            #expect(result.status == 3)
            #expect(server.lastCommand?.name == "accounts list")
            #expect(server.lastCommand?.status == 3)
        }
    }

    @Test(arguments: [true, false])
    func rejectsVersionMismatch(_ wrongProtocol: Bool) throws {
        try withServer { server, socket in
            let protocolVersion = HelperProtocol.version + (wrongProtocol ? 1 : 0)
            let clientVersion = wrongProtocol ? Self.version : "older-version"
            let call = HelperProtocol.Call(protocolVersion: protocolVersion, clientVersion: clientVersion,
                                           command: "accounts list", operation: .accountsList(AccountsListRequest()))
            try socket.send(.call(call))
            #expect(try socket.receive() == .rejected("version_mismatch"))
            #expect(server.lastCommand == nil)
        }
    }

    @Test(arguments: [SIGINT, SIGTERM, SIGHUP])
    func cancelsCallAndReturnsInterrupted(_ signal: Int32) throws {
        let cancelled = DispatchSemaphore(value: 0)
        try withServer(callHandler: { _, _, cancellation in
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                #expect(cancellation.signal == signal)
                cancelled.signal()
            }
            return .init(status: 1)
        }) { server, socket in
            try socket.send(.call(call()))
            try socket.send(.signal(signal))
            let result = try readResult(socket)
            #expect(result.stdout.isEmpty)
            #expect(String(decoding: result.stderr, as: UTF8.self).contains("\"interrupted\""))
            #expect(result.status == 130)
            #expect(server.lastCommand?.status == 130)
            #expect(cancelled.wait(timeout: .now() + 1) == .success)
        }
    }

    private enum TestError: Error { case unexpectedFrame }

    private func call() -> HelperProtocol.Call {
        .init(clientVersion: Self.version, command: "accounts list", operation: .accountsList(AccountsListRequest()))
    }

    private func withServer(
        callHandler: @escaping HelperServer.CallHandler = { _, _, _ in .init(status: 0) },
        _ work: (HelperServer, HelperSocket) throws -> Void
    ) throws {
        let files = FileManager.default
        var template = Array(files.temporaryDirectory.appendingPathComponent("hXXXXXX").path.utf8CString)
        let path = try template.withUnsafeMutableBufferPointer { buffer in
            let directory = try #require(mkdtemp(buffer.baseAddress))
            return String(cString: directory)
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("s")
        let server = try HelperServer(socketURL: socketURL, version: Self.version, callHandler: callHandler)
        defer { server.stop() }
        let socket = try HelperSocket.connect(to: socketURL)
        defer { socket.disconnect() }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        try #require(setsockopt(socket.descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                                socklen_t(MemoryLayout.size(ofValue: timeout))) == 0)
        try work(server, socket)
    }

    private func readResult(_ socket: HelperSocket) throws -> (stdout: Data, stderr: Data, status: Int32) {
        var stdout = Data()
        var stderr = Data()
        while let frame = try socket.receive() {
            switch frame {
            case .stdout(let bytes): stdout.append(bytes)
            case .stderr(let bytes): stderr.append(bytes)
            case .exit(let status): return (stdout, stderr, status)
            default: throw TestError.unexpectedFrame
            }
        }
        throw TestError.unexpectedFrame
    }
}
