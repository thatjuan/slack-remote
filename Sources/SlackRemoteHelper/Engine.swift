import Foundation
import os
import SlackRemoteCore
import SlackRemoteWeb

/// Builds the dependencies for a typed call and encodes its reply.
@MainActor
final class Engine {
    private let pool: SessionPool?
    private let startup: Task<Void, Error>
    private var accountUI: AccountUI?
    private var userDirectories: [TeamID: UserDirectory] = [:]
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    init(pool: SessionPool?) {
        self.pool = pool
        startup = Task { try await pool?.start() }
    }

    func useMenu(_ menu: StatusMenu) {
        accountUI = AccountUI(
            add: { [weak menu] wait, deadline in
                guard let menu else { throw RemoteError.sessionUnavailable }
                return try await menu.addAccount(wait: wait, deadline: deadline)
            },
            remove: { [weak menu] id in
                guard let menu else { throw RemoteError.sessionUnavailable }
                try await menu.removeAccount(id)
            }
        )
    }

    func waitUntilReady() async throws {
        try await startup.value
    }

    func perform(_ call: HelperProtocol.Call, file: FileHandle?) async -> HelperServer.Reply {
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "slack-remote \(call.command)")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let deadline = Date().addingTimeInterval(call.timeout)
        let warnings = OSAllocatedUnfairLock(initialState: [String]())
        do {
            guard call.timeout.isFinite, call.timeout > 0 else { throw RemoteError.timeout }
            try await waitUntilReady()
            try Task.checkCancellation()
            guard Date() < deadline else { throw RemoteError.timeout }
            guard let pool, let accountUI else { throw RemoteError.sessionUnavailable }
            let config = try call.configPath.flatMap { try Config.load(from: URL(fileURLWithPath: $0)) }
            let context = OperationContext(
                deadline: deadline,
                config: config,
                file: file,
                helperVersion: version,
                accounts: { await pool.records },
                api: { team in
                    let selection = try await AccountSelection.resolve(team, in: pool.records)
                    let transport = await WebTransport(pool: pool, accountID: selection.account.id)
                    let workspace = selection.team
                    return SlackAPI(team: workspace.id, user: workspace.user, deadline: deadline, makeTransport: {
                        SessionRefreshingTransport(base: transport, teamName: workspace.name, deadline: deadline,
                                                   refresh: { await transport.refresh(for: workspace.id) },
                                                   signOut: { try await transport.markSignedOut(team: workspace.id) })
                    })
                },
                users: { team in await self.users(team) },
                ui: accountUI,
                warn: { warning in warnings.withLock { $0.append(warning) } }
            )
            return await perform(call.operation.body, command: call.command, context: context, warnings: warnings)
        } catch {
            return failure(call.command, error: remoteError(error), result: nil as Bool?)
        }
    }

    private func users(_ team: TeamID) -> UserDirectory {
        if let directory = userDirectories[team] { return directory }
        let directory = UserDirectory()
        userDirectories[team] = directory
        return directory
    }

    private func perform<Op: RemoteOperation>(_ op: Op, command: String, context: OperationContext,
                                               warnings: OSAllocatedUnfairLock<[String]>) async -> HelperServer.Reply {
        do {
            let result = try await op.run(in: context)
            try Task.checkCancellation()
            return .init(stdout: try Envelope.success(command, result: result, warnings: warnings.withLock { $0 }),
                         status: 0)
        } catch let error as OperationFailure<Op.Output> {
            return failure(command, error: error.error, warnings: warnings.withLock { $0 }, result: error.result)
        } catch {
            return failure(command, error: remoteError(error), warnings: warnings.withLock { $0 }, result: nil as Bool?)
        }
    }

    private func remoteError(_ error: Error) -> RemoteError {
        if Task.isCancelled || error is CancellationError { return .interrupted }
        return error as? RemoteError ?? .internalError(operation: "run_command")
    }

    private func failure<Output: Encodable>(_ command: String, error: RemoteError, warnings: [String] = [],
                                            result: Output?) -> HelperServer.Reply {
        let bytes = try? Envelope.failure(command, error: error, warnings: warnings, result: result)
        return .init(stderr: bytes ?? Data(), status: error.exitStatus)
    }
}
