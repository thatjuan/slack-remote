public enum RemoteError: Error {
    case internalError(operation: String)
    case helperVersionMismatch
    case destinationUnreachable
    case unsafeText(reason: String)
    case draftConflict(existingLength: Int)
    case sendUnconfirmed
    case timeout
    case notImplemented
    case unsupportedDestination
    case writeNotAllowed
    case fileRejected(reason: String)
    case reactionUnconfirmed
    case uploadUnconfirmed
    case interrupted
    case partialResult
    case accountMismatch
    case accountUnverified
    case configInvalid

    public var code: String {
        switch self {
        case .internalError: return "internal"
        case .helperVersionMismatch: return "helper_version_mismatch"
        case .destinationUnreachable: return "destination_unreachable"
        case .unsafeText: return "unsafe_text"
        case .draftConflict: return "draft_conflict"
        case .sendUnconfirmed: return "send_unconfirmed"
        case .timeout: return "timeout"
        case .notImplemented: return "not_implemented"
        case .unsupportedDestination: return "unsupported_destination"
        case .writeNotAllowed: return "write_not_allowed"
        case .fileRejected: return "file_rejected"
        case .reactionUnconfirmed: return "reaction_unconfirmed"
        case .uploadUnconfirmed: return "upload_unconfirmed"
        case .interrupted: return "interrupted"
        case .partialResult: return "partial_result"
        case .accountMismatch: return "account_mismatch"
        case .accountUnverified: return "account_unverified"
        case .configInvalid: return "config_invalid"
        }
    }

    public var exitStatus: Int32 {
        switch self {
        case .internalError, .notImplemented: return 1
        case .helperVersionMismatch: return 10
        case .destinationUnreachable, .unsupportedDestination: return 13
        case .unsafeText, .draftConflict, .writeNotAllowed, .fileRejected: return 15
        case .sendUnconfirmed, .reactionUnconfirmed, .uploadUnconfirmed: return 17
        case .timeout: return 18
        case .partialResult: return 19
        case .accountMismatch, .accountUnverified, .configInvalid: return 20
        case .interrupted: return 130
        }
    }

    public var message: String {
        switch self {
        case .internalError: return "An internal operation failed."
        case .helperVersionMismatch:
            return "SlackRemote.app is a different version from this slack-remote. Quit SlackRemote from the menu bar and run the command again."
        case .destinationUnreachable:
            return "Slack could not reach the requested conversation."
        case .unsafeText: return "Slack remote refused the supplied text."
        case .draftConflict: return "The composer already contains different content."
        case .sendUnconfirmed: return "The message may have been sent. Check the conversation before retrying."
        case .timeout: return "The command deadline passed."
        case .notImplemented: return "This command is not implemented yet."
        case .unsupportedDestination: return "This command does not support the requested destination."
        case .writeNotAllowed: return "The destination is outside the configured write allowlist."
        case .fileRejected: return "Slack remote refused the supplied file."
        case .reactionUnconfirmed: return "The reaction change could not be confirmed."
        case .uploadUnconfirmed: return "The file may have been sent. Check the conversation before retrying."
        case .interrupted: return "The operation was interrupted."
        case .partialResult: return "Paging stopped early. Pass --allow-partial to return the available items."
        case .accountMismatch: return "Slack's signed-in account differs from the configured account."
        case .accountUnverified: return "Slack's signed-in account could not be verified."
        case .configInvalid: return "Slack remote could not read, validate or save its private configuration."
        }
    }

    public enum Detail: Encodable {
        case string(String)
        case integer(Int)
        case boolean(Bool)

        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .string(let text): try value.encode(text)
            case .integer(let number): try value.encode(number)
            case .boolean(let flag): try value.encode(flag)
            }
        }
    }

    public var details: [String: Detail]? {
        switch self {
        case .internalError(let operation): return ["operation": .string(operation)]
        case .unsafeText(let reason), .fileRejected(let reason): return ["reason": .string(reason)]
        case .draftConflict(let existingLength): return ["existingLength": .integer(existingLength)]
        default: return nil
        }
    }
}
