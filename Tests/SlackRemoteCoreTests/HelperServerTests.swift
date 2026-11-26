import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperServerTests {
    private static let version = "test-version"

    @Test func streamsRunnerOutputAndStatus() throws {
        try withServer(script: """
            printf '%s:%s:%s:%s\\n' "$1" "$SLACK_REMOTE_NO_HELPER" "$SLACK_REMOTE_VIA_HELPER" "$SLACK_REMOTE_CONFIG"
            test -f ./runner || exit 8
            echo error >&2
            exit 7
            """) { server, root, socket in
            let config = root.appendingPathComponent("my config.json").path
            let request = HelperProtocol.Request(clientVersion: Self.version, arguments: ["test"],
                                                 workingDirectory: root.path, passesFile: false, configPath: config)
            try socket.send(.request(request))
            let result = try readResult(socket)
            #expect(result.stdout == Data("test:1:test-version:\(config)\n".utf8))
            #expect(result.stderr == Data("error\n".utf8))
            #expect(result.status == 7)
            #expect(server.lastCommand?.name == "test")
            #expect(server.lastCommand?.status == 7)
        }
    }

    @Test func forwardsSignalToRunner() throws {
        try withServer(script: """
            trap 'echo interrupted; exit 130' INT
            echo ready
            while :; do /bin/sleep 0.05; done
            """) { _, root, socket in
            try socket.send(.request(request(root)))
            var ready = Data()
            while ready.count < 6 {
                guard case .stdout(let bytes) = try socket.receive() else { throw TestError.unexpectedFrame }
                ready.append(bytes)
            }
            #expect(ready == Data("ready\n".utf8))
            try socket.send(.signal(SIGINT))
            let result = try readResult(socket)
            #expect(result.stdout == Data("interrupted\n".utf8))
            #expect(result.status == 130)
        }
    }

    @Test func routesPoCCommandsInProcess() throws {
        try withServer(script: "exit 7", inProcess: { request in
            (Data(request.arguments.joined(separator: " ").utf8), Data("test stderr".utf8), 3)
        }) { server, root, socket in
            try socket.send(.request(request(root, arguments: ["webkit-poc", "accounts"])))
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
        try withServer(script: "exit 7") { server, root, socket in
            let request = HelperProtocol.Request(protocolVersion: wrongProtocol ? HelperProtocol.version + 1
                                                    : HelperProtocol.version,
                                                 clientVersion: wrongProtocol ? Self.version : "older-version",
                                                 arguments: ["test"], workingDirectory: root.path, passesFile: false)
            try socket.send(.request(request))
            #expect(try socket.receive() == .rejected("version_mismatch"))
            #expect(server.lastCommand == nil)
        }
    }

    @Test func passesUploadDescriptorAtThree() throws {
        try withServer(script: "/bin/cat /dev/fd/3") { _, root, socket in
            let source = root.appendingPathComponent("source")
            let bytes = Data([0, 42, 255])
            try bytes.write(to: source)
            let file = open(source.path, O_RDONLY | O_CLOEXEC)
            try #require(file >= 0)
            defer { close(file) }
            try FileManager.default.removeItem(at: source)
            try socket.send(.request(request(root, arguments: ["upload"], passesFile: true)), passing: file)
            let result = try readResult(socket)
            #expect(result.stdout == bytes)
            #expect(result.stderr.isEmpty)
            #expect(result.status == 0)
        }
    }

    private enum TestError: Error { case unexpectedFrame }

    private func request(_ root: URL, arguments: [String] = ["test"], passesFile: Bool = false)
        -> HelperProtocol.Request {
        .init(clientVersion: Self.version, arguments: arguments, workingDirectory: root.path, passesFile: passesFile)
    }

    private func withServer(
        script: String,
        inProcess: (@Sendable (HelperProtocol.Request) async -> (stdout: Data, stderr: Data, status: Int32))? = nil,
        _ work: (HelperServer, URL, HelperSocket) throws -> Void
    ) throws {
        let files = FileManager.default
        var template = Array(files.temporaryDirectory.appendingPathComponent("hXXXXXX").path.utf8CString)
        let path = try template.withUnsafeMutableBufferPointer { buffer in
            let directory = try #require(mkdtemp(buffer.baseAddress))
            return String(cString: directory)
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let runner = root.appendingPathComponent("runner")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: runner)
        try #require(chmod(runner.path, 0o700) == 0)
        let socketURL = root.appendingPathComponent("s")
        let server = try HelperServer(socketURL: socketURL, runnerURL: runner, version: Self.version, inProcess: inProcess)
        defer { server.stop() }
        let socket = try HelperSocket.connect(to: socketURL)
        defer { socket.disconnect() }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        try #require(setsockopt(socket.descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                                socklen_t(MemoryLayout.size(ofValue: timeout))) == 0)
        try work(server, root, socket)
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
