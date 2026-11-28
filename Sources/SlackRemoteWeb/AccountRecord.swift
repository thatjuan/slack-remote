import Darwin
import Foundation

struct AccountRecord: Codable {
    struct Team: Codable {
        let id: String
        let name: String
        let url: String
        let userID: String

        init(_ team: LocalConfig.Team) {
            id = team.id
            name = team.name
            url = team.url
            userID = team.userID
        }
    }

    let storeID: UUID
    let teams: [Team]

    private static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/slack-remote", isDirectory: true)
            .appendingPathComponent("poc-accounts.json")
    }

    static func read() throws -> [Self] {
        do {
            return try JSONDecoder().decode([Self].self, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
    }

    static func append(_ account: Self) throws {
        let file = Self.file
        let directory = file.deletingLastPathComponent()
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let records = try read() + [account]
        let data = try JSONEncoder().encode(records)
        let staged = directory.appendingPathComponent(".poc-accounts-\(UUID().uuidString)")
        defer { try? files.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        guard rename(staged.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
