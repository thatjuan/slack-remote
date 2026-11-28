import Foundation
import os
import SlackRemoteCore
import WebKit

/// Owns the account inventory and its background browser profiles on the main actor.
@MainActor
public final class SessionPool {
    private static let log = Logger(subsystem: "com.thatjuan.slack-remote.helper", category: "profiles")

    private var file: AccountFile
    private var sessions: [AccountID: SlackSession] = [:]

    public init(file: AccountFile) {
        self.file = file
    }

    public var records: [AccountRecord] { file.accounts }
    public var onChange: (() -> Void)?

    /// Reconcile once before sign-in can create a profile of its own.
    public func start() async throws {
        // WebKit needs a data store initialized before it can enumerate persistent identifiers.
        _ = WKWebsiteDataStore.default()
        let storeIDs = Set(await WKWebsiteDataStore.allDataStoreIdentifiers)
        let reconciliation = AccountStore.reconcile(file, storeIDs: storeIDs)
        var next = file
        for index in next.accounts.indices where reconciliation.missingStores.contains(next.accounts[index].id) {
            next.accounts[index].state = .signedOut
        }
        if next != file { try persist(next) }
        for id in reconciliation.orphanStores {
            do { try await Self.removeStore(id) }
            catch { NSLog("SlackRemote could not remove an unused browser profile.") }
        }
        for record in records where storeIDs.contains(record.id.rawValue) {
            startSession(SlackSession(storeID: record.id.rawValue), for: record.id)
        }
    }

    /// Find the single profile that owns the team.
    func session(for team: TeamID) -> (AccountRecord, SlackSession)? {
        guard let record = records.first(where: { $0.teams.contains { $0.id == team } }),
              let session = sessions[record.id] else { return nil }
        return (record, session)
    }

    /// Commit the record before adopting its browser session.
    func add(_ record: AccountRecord, session: SlackSession) throws {
        var next = file
        next.accounts.append(record)
        try persist(next)
        startSession(session, for: record.id)
    }

    func update(_ record: AccountRecord) throws {
        var next = file
        guard let index = next.accounts.firstIndex(where: { $0.id == record.id }) else {
            throw AccountStore.InvalidFile.unreadable
        }
        next.accounts[index] = record
        try persist(next)
        if sessions[record.id] == nil {
            startSession(SlackSession(storeID: record.id.rawValue), for: record.id)
        }
    }

    /// Persist removal first so a failed save leaves the account and its session intact.
    public func remove(_ id: AccountID) async throws {
        guard records.contains(where: { $0.id == id }) else { return }
        var next = file
        next.accounts.removeAll { $0.id == id }
        try persist(next)
        sessions.removeValue(forKey: id)?.close()
        try await Self.removeStore(id.rawValue)
    }

    /// Remove a profile once its web views have been released.
    static func removeStore(_ id: UUID) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while await WKWebsiteDataStore.allDataStoreIdentifiers.contains(id) {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                break
            } catch {
                // The network process can still be releasing the profile after its last view closes.
                guard ContinuousClock.now < deadline else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        let remaining = await WKWebsiteDataStore.allDataStoreIdentifiers
        log.notice("Profiles after removing \(id.uuidString, privacy: .public): \(remaining.map(\.uuidString).sorted().joined(separator: ", "), privacy: .public)")
    }

    private func startSession(_ session: SlackSession, for id: AccountID) {
        sessions[id] = session
        Task { try? await session.prepare() }
    }

    private func persist(_ next: AccountFile) throws {
        try AccountStore.save(next)
        file = next
        onChange?()
    }
}
