import Foundation
@testable import SlackRemoteCore
import Testing

@MainActor
struct SlackAppTests {
    private enum BodyError: Error { case failed }

    private let identity = ProcessIdentity(pid: 12345, launchDate: Date(timeIntervalSince1970: 100))

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    @Test func leavesAnAlreadyPresentUnmarkedTreeAlone() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var modeChanges: [Bool] = []
        let app = SlackApp(identity: identity, supportDirectory: directory, readWindows: { [SlackFixture.window()] },
                           setMode: { modeChanges.append($0) })
        let mode = try app.withTree(deadline: Date().addingTimeInterval(2)) { $0.sessionInfo?.mode }
        #expect(mode == .alreadyPresent)
        #expect(modeChanges.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func restoresOwnedModeWhenTheBodyThrows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var modeChanges: [Bool] = []
        let app = SlackApp(identity: identity, supportDirectory: directory,
                           readWindows: { modeChanges.last == true ? [SlackFixture.window()] : [] },
                           setMode: { modeChanges.append($0) })
        #expect(throws: BodyError.failed) {
            try app.withTree(deadline: Date().addingTimeInterval(2)) { tree in
                #expect(tree.sessionInfo?.mode == .enabled)
                #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ax-enabled-12345").path))
                throw BodyError.failed
            }
        }
        #expect(modeChanges == [true, false])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func waitsForParseableClientURLAndReportsLostTreeDuringRefresh() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let window = SlackFixture.window()
        let web = try #require(try window.one(Locators.webArea) as? FakeNode)
        let valid = web.attributes[.url]
        var reads = 0
        let app = SlackApp(identity: identity, supportDirectory: directory,
                           readWindows: {
            reads += 1
            web.attributes[.url] = (3...4).contains(reads) ? valid : .string("https://slack.com")
            return [window]
        }, setMode: { _ in })
        try app.withTree(deadline: Date().addingTimeInterval(2)) { tree in
            #expect(reads == 4)
            let error = #expect(throws: RemoteError.self) { try tree.refresh() }
            #expect(error?.code == "tree_unavailable")
        }
    }
}
