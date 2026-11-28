import Foundation

/// Display names for one team, cached in the helper for an hour.
public actor UserDirectory {
    private struct Entry {
        let name: String
        let expires: Date
    }

    private let api: SlackAPI?
    private let now: @Sendable () -> Date
    private var cache: [UserID: Entry] = [:]
    private var activeLookups = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// An API supplied here can be used for lookups outside an operation context.
    public init(api: SlackAPI? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.api = api
        self.now = now
    }

    public func names(for ids: Set<UserID>) async throws -> [UserID: String] {
        guard let api else { throw RemoteError.sessionUnavailable }
        return try await names(for: ids, using: api)
    }

    /// Use the current command's API and deadline when looking up uncached names.
    func names(for ids: Set<UserID>, using api: SlackAPI) async throws -> [UserID: String] {
        var names: [UserID: String] = [:]
        var unknown: [UserID] = []
        for id in ids {
            if let name = cachedName(for: id) { names[id] = name }
            else { unknown.append(id) }
        }

        try await withThrowingTaskGroup(of: (UserID, String?).self) { group in
            var remaining = unknown.makeIterator()
            for _ in 0..<4 {
                guard let id = remaining.next() else { break }
                group.addTask { (id, try await self.lookup(id, using: api)) }
            }
            while let (id, name) = try await group.next() {
                names[id] = name
                if let next = remaining.next() {
                    group.addTask { (next, try await self.lookup(next, using: api)) }
                }
            }
        }
        return names
    }

    public func seed(_ users: [SlackUser]) {
        let expires = now().addingTimeInterval(3600)
        for user in users {
            if let name = user.displayLabel {
                cache[user.id] = Entry(name: name, expires: expires)
            }
        }
    }

    private func cachedName(for id: UserID) -> String? {
        guard let entry = cache[id], now() < entry.expires else { return nil }
        return entry.name
    }

    private func lookup(_ id: UserID, using api: SlackAPI) async throws -> String? {
        // Several commands can look up names in this workspace at once.
        if activeLookups == 4 {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            activeLookups += 1
        }
        defer {
            if waiting.isEmpty { activeLookups -= 1 }
            else { waiting.removeFirst().resume() }
        }

        if let name = cachedName(for: id) { return name }
        do {
            let response = try await api.call("users.info", ["user": id.rawValue], as: SlackUserInfo.self)
            seed([response.user])
            return response.user.displayLabel
        } catch RemoteError.slackAPI(method: "users.info", error: "user_not_found") {
            return nil
        } catch RemoteError.timeout {
            // Keep paged rows and cached names when the deadline leaves no time for a lookup.
            return nil
        }
    }
}
