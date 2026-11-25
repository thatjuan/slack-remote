import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct FileStagingTests {
    @Test func fileRejections() throws {
        try withDirectory { root in
            func reject(_ name: String, reason: String, maxSize: Int = FileStaging.defaultLimit) {
                expectRejection(reason) { _ = try FileStaging(path: root.appendingPathComponent(name).path,
                                                               maxSize: maxSize) }
            }
            let files = [".hidden", "line\nbreak", "file:name", "large", "secret"]
            for name in files {
                try Data([1, 2]).write(to: root.appendingPathComponent(name))
            }
            try Data().write(to: root.appendingPathComponent("empty"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"),
                                                    withIntermediateDirectories: false)
            #expect(mkfifo(root.appendingPathComponent("fifo").path, 0o600) == 0)
            reject("missing", reason: "missing")
            reject("folder", reason: "not_regular")
            reject("fifo", reason: "not_regular")
            reject(".hidden", reason: "invalid_name")
            reject("line\nbreak", reason: "invalid_name")
            reject("file:name", reason: "invalid_name")
            reject("empty", reason: "empty")
            reject("large", reason: "too_large", maxSize: 1)
            reject("large", reason: "invalid_size_limit", maxSize: 0)
            reject("large", reason: "invalid_size_limit", maxSize: FileStaging.maximumLimit + 1)
            let unreadable = root.appendingPathComponent("secret")
            #expect(chmod(unreadable.path, 0) == 0)
            if geteuid() != 0 { reject("secret", reason: "unreadable") }
        }
    }

    @Test func copiesResolvedSourceUsingRequestedNameAndCleansUp() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source")
            let requested = root.appendingPathComponent("synthetic.txt")
            let bytes = Data([1, 2, 3])
            try bytes.write(to: source)
            try FileManager.default.createSymbolicLink(at: requested, withDestinationURL: source)
            let local = try FileStaging(path: requested.path, maxSize: bytes.count)
            #expect(local.file.name == requested.lastPathComponent)
            #expect(local.file.bytes == bytes.count)

            let directory = try local.withStagedFile(in: root) { staged in
                #expect(staged.lastPathComponent == requested.lastPathComponent)
                let copied = try Data(contentsOf: staged)
                #expect(copied == bytes)
                return staged.deletingLastPathComponent()
            }
            #expect(!FileManager.default.fileExists(atPath: directory.path))

            struct Failure: Error {}
            var abandoned: URL?
            #expect(throws: Failure.self) {
                try local.withStagedFile(in: root) { staged in
                    abandoned = staged.deletingLastPathComponent()
                    throw Failure()
                }
            }
            #expect(!FileManager.default.fileExists(atPath: try #require(abandoned).path))
            #expect(try Data(contentsOf: source) == bytes)
        }
    }

    @Test func refusesAReplacementSource() throws {
        try withDirectory { root in
            let url = root.appendingPathComponent("synthetic.txt")
            try Data([1]).write(to: url)
            let file = try FileStaging(path: url.path)
            try Data([2]).write(to: url, options: .atomic)
            expectRejection("source_changed") {
                try file.withStagedFile(in: root) { _ in
                    Issue.record("Unexpected staging")
                } as Void
            }
        }
    }

    @Test func stagesAnOpenDescriptorByItsSuppliedName() throws {
        try withDirectory { root in
            let source = root.appendingPathComponent("source")
            let bytes = Data([1, 2, 3])
            try bytes.write(to: source)
            let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            try #require(fd >= 0)
            defer { close(fd) }
            try FileManager.default.removeItem(at: source)
            let path = "/dev/fd/\(fd)"
            let file = try FileStaging(path: path, name: "original.txt")
            #expect(file.file.bytes == bytes.count)
            try file.withStagedFile(in: root) { staged in
                #expect(staged.lastPathComponent == "original.txt")
                let copied = try Data(contentsOf: staged)
                #expect(copied == bytes)
            }
            expectRejection("invalid_name") { _ = try FileStaging(path: path, name: "../invalid") }
        }
    }

    private func expectRejection(_ reason: String, _ work: () throws -> Void) {
        do {
            try work()
            Issue.record("Expected file_rejected")
        } catch RemoteError.fileRejected(let observed) {
            #expect(observed == reason)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func withDirectory(_ work: (URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/upload-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try work(root)
    }
}
