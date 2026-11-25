import Darwin
import Foundation

public struct FileStaging {
    public static let defaultLimit = 50_000_000
    public static let maximumLimit = 1_000_000_000

    public struct File: Encodable {
        public let name: String
        public let bytes: Int
    }

    public let file: File
    private let source: URL
    private let identity: Identity

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            size = status.st_size
            modifiedSeconds = status.st_mtimespec.tv_sec
            modifiedNanoseconds = status.st_mtimespec.tv_nsec
            changedSeconds = status.st_ctimespec.tv_sec
            changedNanoseconds = status.st_ctimespec.tv_nsec
        }
    }

    public init(path: String, name: String? = nil, maxSize: Int = Self.defaultLimit) throws {
        guard (1...Self.maximumLimit).contains(maxSize) else {
            throw RemoteError.fileRejected(reason: "invalid_size_limit")
        }
        guard !path.isEmpty else { throw RemoteError.fileRejected(reason: "missing") }
        let requested = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        let name = name ?? requested.lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"),
              !name.contains("\\"), name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw RemoteError.fileRejected(reason: "invalid_name")
        }

        let resolved = requested.resolvingSymlinksInPath()
        let input = try Self.openSource(resolved)
        defer { try? input.close() }
        let identity = try Self.identity(of: input)
        guard identity.size > 0 else { throw RemoteError.fileRejected(reason: "empty") }
        guard identity.size <= maxSize else { throw RemoteError.fileRejected(reason: "too_large") }
        self.identity = identity
        source = resolved
        file = File(name: name, bytes: Int(identity.size))
    }

    private static func openSource(_ source: URL) throws -> FileHandle {
        // O_NONBLOCK avoids blocking if the path changes to a FIFO before the type check.
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw RemoteError.fileRejected(reason: errno == ENOENT || errno == ENOTDIR ? "missing" : "unreadable")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func identity(of input: FileHandle) throws -> Identity {
        var status = stat()
        guard fstat(input.fileDescriptor, &status) == 0 else {
            throw RemoteError.fileRejected(reason: "unreadable")
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw RemoteError.fileRejected(reason: "not_regular")
        }
        return Identity(status)
    }

    func withStagedFile<T>(in downloads: URL, _ work: (URL) throws -> T) throws -> T {
        let input = try Self.openSource(source)
        defer { try? input.close() }
        guard try Self.identity(of: input) == identity else {
            throw RemoteError.fileRejected(reason: "source_changed")
        }

        let directory = downloads.resolvingSymlinksInPath()
            .appendingPathComponent("slack-remote-upload-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(directory.path, 0o700) == 0 else {
            throw RemoteError.fileRejected(reason: "staging_failed")
        }
        let result = Result {
            let staged = directory.appendingPathComponent(file.name, isDirectory: false)
            try copy(input, to: staged)
            return try work(staged)
        }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            if FileManager.default.fileExists(atPath: directory.path) {
                throw RemoteError.internalError(operation: "remove_upload_staging")
            }
        }
        return try result.get()
    }

    private func copy(_ input: FileHandle, to staged: URL) throws {
        let fd = open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw RemoteError.fileRejected(reason: "staging_failed") }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close() }
        var remaining = file.bytes
        do {
            while remaining > 0 {
                guard let chunk = try input.read(upToCount: min(remaining, 1_048_576)), !chunk.isEmpty else {
                    throw RemoteError.fileRejected(reason: "source_changed")
                }
                try output.write(contentsOf: chunk)
                remaining -= chunk.count
            }
            try output.close()
        } catch let error as RemoteError {
            throw error
        } catch {
            throw RemoteError.fileRejected(reason: "staging_failed")
        }
        guard try Self.identity(of: input) == identity else {
            throw RemoteError.fileRejected(reason: "source_changed")
        }
    }
}
