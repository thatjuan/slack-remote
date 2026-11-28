import Foundation
import SlackRemoteCore
import Testing

struct AccountStoreTests {
    @Test func roundTripUsesPrivateISO8601File() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = AccountFile(accounts: [account()])
        try AccountStore.save(first, to: url)
        #expect(try AccountStore.load(from: url) == first)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect(directory[.posixPermissions] as? Int == 0o700)
        #expect(try String(contentsOf: url, encoding: .utf8).contains("2023-11-14T22:13:20Z"))

        var next = first
        next.accounts[0].state = .signedOut
        try AccountStore.save(next, to: url)
        #expect(try AccountStore.load(from: url) == next)
    }

    @Test func missingFileIsEmpty() throws {
        #expect(try AccountStore.load(from: temporaryFile()) == AccountFile())
    }

    @Test(arguments: [0o640, 0o604])
    func refusesReadableByOtherUsers(mode: Int) throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try AccountStore.save(AccountFile(accounts: [account()]), to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        let original = try Data(contentsOf: url)
        #expect(throws: AccountStore.InvalidFile.self) { try AccountStore.load(from: url) }
        #expect(throws: AccountStore.InvalidFile.self) { try AccountStore.save(AccountFile(), to: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test(arguments: [false, true])
    func rejectsDuplicateIdentity(sameAccount: Bool) throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = account()
        let duplicate = sameAccount ? account(id: first.id, team: "T0BBBBBBB") : account()
        let invalid = AccountFile(accounts: [first, duplicate])
        #expect(throws: AccountStore.InvalidFile.self) { try AccountStore.save(invalid, to: url) }

        try AccountStore.save(AccountFile(), to: url)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(invalid).write(to: url)
        #expect(throws: AccountStore.InvalidFile.self) { try AccountStore.load(from: url) }
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func reconciliation(orphan: Bool, missing: Bool) {
        let present = account()
        let absent = account(team: "T0BBBBBBB")
        let abandoned = UUID()
        let file = AccountFile(accounts: missing ? [present, absent] : [present])
        let stores: Set<UUID> = orphan ? [present.id.rawValue, abandoned] : [present.id.rawValue]
        let result = AccountStore.reconcile(file, storeIDs: stores)
        #expect(result.orphanStores == (orphan ? [abandoned] : []))
        #expect(result.missingStores == (missing ? [absent.id] : []))
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("accounts.json")
    }

    private func account(id: AccountID = AccountID(), team: String = "T0AAAAAAA") -> AccountRecord {
        AccountRecord(id: id, teams: [
            .init(id: TeamID(team)!, name: "Acme", url: URL(string: "https://acme.slack.com/")!,
                  user: UserID("U0AAAAAAA")!, userName: "Ada"),
        ], state: .active, addedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }
}
