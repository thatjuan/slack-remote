import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperServerTests {
    private static let version = "test-version"

    @Test func routesPoCCommandsInProcess() throws {
        try withServer(inProcess: { request in
            (Data(request.arguments.joined(separator: " ").utf8), Data("test stderr".utf8), 3)
        }) { server, socket in
            try socket.send(.request(request(arguments: ["webkit-poc", "accounts"])))
            let result = try readResult(socket)
            #expect(result.stdout == Data("webkit-poc accounts".utf8))
            #expect(result.stderr == Data("test stderr".utf8))
            #expect(result.status == 3)
            #expect(server.lastCommand?.name == "webkit-poc")
            #expect(server.lastCommand?.status == 3)
        }
    }

    @Test(arguments: [true, false])
    func rejectsVersionMismatch(_ wrongProtocol: Bool) throws {
        try withServer { server, socket in
            let protocolVersion = HelperProtocol.version + (wrongProtocol ? 1 : 0)
            let clientVersion = wrongProtocol ? Self.version : "older-version"
            let request = HelperProtocol.Request(protocolVersion: protocolVersion, clientVersion: clientVersion,
                                                 arguments: ["webkit-poc", "accounts"])
            try socket.send(.request(request))
            #expect(try socket.receive() == .rejected("version_mismatch"))
            #expect(server.lastCommand == nil)
        }
    }

    @Test(arguments: [[], ["dest", "list"]])
    func rejectsUnsupportedArguments(_ arguments: [String]) throws {
        try withServer { server, socket in
            try socket.send(.request(request(arguments: arguments)))
            #expect(try socket.receive() == .rejected("unsupported"))
            #expect(server.lastCommand == nil)
        }
    }

    private enum TestError: Error { case unexpectedFrame }

    private func request(arguments: [String]) -> HelperProtocol.Request {
        .init(clientVersion: Self.version, arguments: arguments)
    }

    private func withServer(
        inProcess: @escaping @Sendable (HelperProtocol.Request) async -> (stdout: Data, stderr: Data, status: Int32)
            = { _ in (Data(), Data(), 0) },
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
        let server = try HelperServer(socketURL: socketURL, version: Self.version, inProcess: inProcess)
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
