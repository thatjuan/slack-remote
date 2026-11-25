import Darwin
import Foundation

public enum CommandLock {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/slack-remote", isDirectory: true)
    }

    public static func acquire(deadline: Date) throws {
        guard Date() < deadline else { throw RemoteError.timeout }
        let directory = supportDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw RemoteError.internalError(operation: "create_lock_directory")
        }

        let descriptor = open(directory.appendingPathComponent("lock").path,
                              O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw RemoteError.internalError(operation: "open_lock") }

        var acquired = false
        defer { if !acquired { close(descriptor) } }
        guard Date() < deadline else { throw RemoteError.timeout }
        while Date() < deadline {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                // Keep this descriptor open until process exit so that no command can overlap the restore.
                acquired = true
                return
            }
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw RemoteError.internalError(operation: "acquire_lock")
            }
            Poll.wait(until: deadline)
        }
        throw RemoteError.busy
    }
}
