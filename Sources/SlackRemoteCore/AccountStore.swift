import Darwin
import Foundation

/// Reads and atomically replaces the helper's private account inventory.
public enum AccountStore {
    public enum InvalidFile: Error { case unreadable }

    public static var fileURL: URL {
        SupportDirectory.url.appendingPathComponent("accounts.json")
    }

    /// A missing file represents a fresh installation.
    public static func load(from url: URL = fileURL) throws -> AccountFile {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT { return AccountFile() }
            throw InvalidFile.unreadable
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o600 else {
            throw InvalidFile.unreadable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let accounts = try decoder.decode(AccountFile.self, from: file.readToEnd() ?? Data())
            try validate(accounts)
            return accounts
        } catch {
            throw InvalidFile.unreadable
        }
    }

    /// Stage a private file beside the destination so readers see a complete snapshot.
    public static func save(_ accounts: AccountFile, to url: URL = fileURL) throws {
        try validate(accounts)
        _ = try load(from: url)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw InvalidFile.unreadable }
        defer { close(directoryFD) }
        var info = stat()
        guard fstat(directoryFD, &info) == 0, info.st_uid == geteuid(),
              fchmod(directoryFD, 0o700) == 0 else { throw InvalidFile.unreadable }

        var path = Array(directory.appendingPathComponent(".accounts.XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&path)
        guard descriptor >= 0 else { throw InvalidFile.unreadable }
        let temporary = String(cString: path)
        defer { unlink(temporary) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fchmod(descriptor, 0o600) == 0 else { throw InvalidFile.unreadable }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try file.write(contentsOf: encoder.encode(accounts) + Data([0x0a]))
        try file.close()
        guard rename(temporary, url.path) == 0 else { throw InvalidFile.unreadable }
    }

    public struct Reconciliation: Equatable {
        public let orphanStores: Set<UUID>
        public let missingStores: Set<AccountID>
    }

    /// Identify abandoned sign-ins and accounts whose profile is missing without touching either store.
    public static func reconcile(_ file: AccountFile, storeIDs: Set<UUID>) -> Reconciliation {
        let recorded = Set(file.accounts.map(\.id))
        return Reconciliation(orphanStores: storeIDs.subtracting(recorded.map(\.rawValue)),
                              missingStores: recorded.filter { !storeIDs.contains($0.rawValue) })
    }

    private static func validate(_ file: AccountFile) throws {
        let teamIDs = file.accounts.flatMap { $0.teams.map(\.id) }
        let ids = Set(file.accounts.map(\.id))
        // WebKit rejects the all-zero profile identifier with an Objective-C exception.
        let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard file.version == 1, ids.count == file.accounts.count, !ids.contains(AccountID(rawValue: zero)),
              Set(teamIDs).count == teamIDs.count, file.accounts.allSatisfy({ !$0.teams.isEmpty }) else {
            throw InvalidFile.unreadable
        }
    }
}
