import AppKit
import Darwin
import Foundation
import SlackRemoteCore

/// Sends a parsed command to SlackRemote.app and streams its reply.
enum HelperClient {
    static func call(command: String, operation: SlackRemoteCore.Operation, timeout: Double, file: Int32? = nil) -> Int32 {
        guard let connection = connectOrLaunch() else {
            return fail(command, error: .helperUnavailable)
        }
        defer { connection.disconnect() }

        let call = HelperProtocol.Call(clientVersion: SlackRemoteVersion.current, command: command,
                                       operation: operation, timeout: timeout, configPath: Config.fileURL.path,
                                       passesFile: file != nil)
        let queue = DispatchQueue(label: "slack-remote.client.signals")
        // Defer forwarding until the initial call has been written to the socket.
        queue.suspend()
        let signals = [SIGINT, SIGTERM, SIGHUP].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { try? connection.send(.signal(number)) }
            source.activate()
            return source
        }
        defer { signals.forEach { $0.cancel() } }
        do {
            try connection.send(.call(call), passing: file)
        } catch {
            queue.resume()
            return fail(command, error: .helperUnavailable)
        }
        queue.resume()
        do { return try receiveResult(from: connection, command: command) }
        catch { return fail(command, error: .helperUnavailable) }
    }

    private static func connectOrLaunch() -> HelperSocket? {
        let socket = HelperProtocol.socketURL
        if let connection = try? HelperSocket.connect(to: socket) { return connection }
        let files = FileManager.default
        let candidates = [
            files.homeDirectoryForCurrentUser.appendingPathComponent("Applications/SlackRemote.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/SlackRemote.app", isDirectory: true),
        ]
        guard let app = candidates.first(where: { files.fileExists(atPath: $0.path) }) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: nil)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.1)))
            if let connection = try? HelperSocket.connect(to: socket) { return connection }
        }
        return nil
    }

    private static func receiveResult(from connection: HelperSocket, command: String) throws -> Int32 {
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
            case .call, .signal:
                return fail(command, error: .internalError(operation: "helper_invalid_response"))
            }
        }
        return fail(command, error: .helperUnavailable)
    }

    private static func fail(_ command: String, error: RemoteError) -> Int32 {
        try? Envelope.writeFailure(command, error: error)
        return error.exitStatus
    }
}
