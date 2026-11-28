import Foundation

/// One CLI command's typed request, executed in the helper.
public protocol RemoteOperation: Codable, Sendable {
    associatedtype Output: Encodable & Sendable
    func run(in context: OperationContext) async throws -> Output
}

public enum Operation: Codable, Equatable, Sendable {
    case doctor(DoctorRequest)
    case whoami(WhoamiRequest)
    case accountsList(AccountsListRequest)
    case accountsAdd(AccountsAddRequest)
    case accountsRemove(AccountsRemoveRequest)

    public var body: any RemoteOperation {
        switch self {
        case .doctor(let request): return request
        case .whoami(let request): return request
        case .accountsList(let request): return request
        case .accountsAdd(let request): return request
        case .accountsRemove(let request): return request
        }
    }
}

/// The output an operation collected before failing.
public struct OperationFailure<Output: Encodable & Sendable>: Error {
    public let error: RemoteError
    public let result: Output

    public init(error: RemoteError, result: Output) {
        self.error = error
        self.result = result
    }
}

/// The account actions that need the helper's UI.
public struct AccountUI: Sendable {
    public let add: @Sendable (_ wait: Bool, _ deadline: Date) async throws -> [TeamID]?
    public let remove: @Sendable (AccountID) async throws -> Void

    public init(add: @escaping @Sendable (Bool, Date) async throws -> [TeamID]?,
                remove: @escaping @Sendable (AccountID) async throws -> Void) {
        self.add = add
        self.remove = remove
    }
}

/// Call-scoped dependencies for operations running in the helper.
public struct OperationContext: Sendable {
    public let deadline: Date
    public let config: Config?
    public let file: FileHandle?
    public let helperVersion: String
    public let accounts: @Sendable () async -> [AccountRecord]
    public let api: @Sendable (TeamID?) async throws -> SlackAPI
    public let ui: AccountUI
    public let warn: @Sendable (String) -> Void

    public init(deadline: Date, config: Config?, file: FileHandle? = nil, helperVersion: String,
                accounts: @escaping @Sendable () async -> [AccountRecord],
                api: @escaping @Sendable (TeamID?) async throws -> SlackAPI, ui: AccountUI,
                warn: @escaping @Sendable (String) -> Void) {
        self.deadline = deadline
        self.config = config
        self.file = file
        self.helperVersion = helperVersion
        self.accounts = accounts
        self.api = api
        self.ui = ui
        self.warn = warn
    }
}
