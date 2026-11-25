import AppKit
import Darwin
import Foundation
import SlackRemoteCore

enum HelperClient {
    enum UnusedReason: String {
        case disabled
        case notInstalled = "not_installed"
        case notRunning = "not_running"
    }

    private(set) static var unusedReason: UnusedReason = .notInstalled

    static func forwardIfAvailable(arguments: [String]) -> Int32? {
        let environment = ProcessInfo.processInfo.environment
        let disabled = environment["SLACK_REMOTE_NO_HELPER"]
        guard HelperForwarding.shouldForward(arguments: arguments, noHelper: disabled),
              let command = arguments.first else {
            if disabled == "1" { unusedReason = .disabled }
            return nil
        }
        guard let connection = connectOrLaunch() else { return nil }
        defer { connection.disconnect() }

        var file: Int32?
        var forwarded = arguments
        if command == "upload", let parsed = try? Upload.parse(Array(arguments.dropFirst())), !parsed.file.isEmpty {
            guard let upload = HelperForwarding.rewriteUpload(arguments: arguments), upload.path == parsed.file
            else { return nil }
            let requested = URL(fileURLWithPath: NSString(string: upload.path).expandingTildeInPath)
            let fd = open(requested.resolvingSymlinksInPath().path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { return nil }
            file = fd
            forwarded = upload.arguments
        }
        let configPath = environment["SLACK_REMOTE_CONFIG"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0).path }
        let request = HelperProtocol.Request(clientVersion: SlackRemoteVersion.current, arguments: forwarded,
                                             workingDirectory: FileManager.default.currentDirectoryPath,
                                             passesFile: file != nil, configPath: configPath)
        do {
            do {
                defer { if let file { close(file) } }
                try connection.send(.request(request), passing: file)
            }
            return try receiveResult(from: connection, command: command)
        } catch {
            return fail(command, error: .internalError(operation: "helper_disconnected"))
        }
    }

    private static func connectOrLaunch() -> HelperSocket? {
        let socket = HelperProtocol.socketURL
        if let connection = try? HelperSocket.connect(to: socket) { return connection }
        let files = FileManager.default
        let candidates = [
            files.homeDirectoryForCurrentUser.appendingPathComponent("Applications/SlackRemote.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/SlackRemote.app", isDirectory: true),
        ]
        guard let app = candidates.first(where: { files.fileExists(atPath: $0.path) }) else {
            unusedReason = .notInstalled
            return nil
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: nil)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.1)))
            if let connection = try? HelperSocket.connect(to: socket) { return connection }
        }
        unusedReason = .notRunning
        return nil
    }

    private static func receiveResult(from connection: HelperSocket, command: String) throws -> Int32 {
        let signals = [SIGINT, SIGTERM, SIGHUP].map { number in
            let previous = signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler { try? connection.send(.signal(number)) }
            source.activate()
            return (number, previous, source)
        }
        defer {
            for (number, previous, source) in signals {
                source.cancel()
                signal(number, previous)
            }
        }
        while let frame = try connection.receive() {
            switch frame {
            case .stdout(let bytes):
                try FileHandle.standardOutput.write(contentsOf: bytes)
            case .stderr(let bytes):
                try FileHandle.standardError.write(contentsOf: bytes)
            case .exit(let status):
                return status
            case .rejected("version_mismatch"):
                return fail(command, error: .helperVersionMismatch)
            case .rejected(let reason):
                return fail(command, error: .internalError(operation: "helper_\(reason)"))
            case .request, .signal:
                return fail(command, error: .internalError(operation: "helper_invalid_response"))
            }
        }
        return fail(command, error: .internalError(operation: "helper_disconnected"))
    }

    private static func fail(_ command: String, error: RemoteError) -> Int32 {
        try? CommandSupport.writeFailure(command, error: error, result: nil as Bool?)
        return error.exitStatus
    }
}
