import AppKit
import Foundation
import SlackRemoteCore

/// Sends the WebKit PoC command to the running helper.
enum HelperClient {
    static func forward(arguments: [String]) -> Int32 {
        let command = "webkit-poc"
        guard let connection = connectOrLaunch() else {
            return fail(command, error: .internalError(operation: "helper_unavailable"))
        }
        defer { connection.disconnect() }

        let request = HelperProtocol.Request(clientVersion: SlackRemoteVersion.current, arguments: arguments)
        do {
            try connection.send(.request(request))
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
            case .request:
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
