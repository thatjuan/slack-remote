import Darwin
import Foundation

public struct Config: Codable, Sendable {
    public var destinations: [String: Destination] = [:]
    public var restrictWritesToDestinations = false

    public init() {}

    public static var fileURL: URL {
        if let path = ProcessInfo.processInfo.environment["SLACK_REMOTE_CONFIG"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/slack-remote/config.json")
    }

    public static func isValidName(_ name: String) -> Bool {
        name.wholeMatch(of: #/[a-z0-9_-]{1,32}/#) != nil
    }

    public static func load(from url: URL = fileURL) throws -> Config? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw RemoteError.configInvalid
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
            throw RemoteError.configInvalid
        }
        do {
            let data = try file.readToEnd() ?? Data()
            let config = try JSONDecoder().decode(Config.self, from: data)
            try config.validate()
            return config
        } catch {
            throw RemoteError.configInvalid
        }
    }

    /// Serializes destination edits within this config directory to avoid losing concurrent updates.
    public static func setDestination(_ destination: Destination, named name: String,
                                      deadline: Date, at url: URL = fileURL) throws -> Config {
        let directory = try createDirectory(for: url)
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw RemoteError.configInvalid }
        defer { close(descriptor) }

        while Date() < deadline {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                var config = try load(from: url) ?? Config()
                config.destinations[name] = destination
                try config.save(to: url)
                return config
            }
            guard errno == EWOULDBLOCK || errno == EINTR else { throw RemoteError.configInvalid }
            Thread.sleep(forTimeInterval: min(0.05, max(0, deadline.timeIntervalSinceNow)))
        }
        throw RemoteError.timeout
    }

    /// Replaces the config atomically using a private temporary file in the same directory.
    public func save(to url: URL = fileURL) throws {
        try validate()
        let directory = try Self.createDirectory(for: url)
        do {
            var path = Array(directory.appendingPathComponent(".slack-remote.XXXXXX").path.utf8CString)
            let descriptor = mkstemp(&path)
            guard descriptor >= 0 else { throw RemoteError.configInvalid }
            let temporary = String(cString: path)
            defer { unlink(temporary) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? file.close() }
            guard fchmod(descriptor, 0o600) == 0 else { throw RemoteError.configInvalid }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try file.write(contentsOf: encoder.encode(self) + Data([0x0a]))
            try file.close()
            guard rename(temporary, url.path) == 0 else { throw RemoteError.configInvalid }
        } catch {
            throw RemoteError.configInvalid
        }
    }

    private static func createDirectory(for url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            return directory
        } catch {
            throw RemoteError.configInvalid
        }
    }

    public func requireWriteAllowed(to destination: Destination) throws {
        if restrictWritesToDestinations && !destinations.values.contains(destination) {
            throw RemoteError.writeNotAllowed
        }
    }

    private func validate() throws {
        guard destinations.keys.allSatisfy(Self.isValidName) else {
            throw RemoteError.configInvalid
        }
    }
}
