public enum RemoteError: Error {
    case internalError(operation: String)
    case axFailure(operation: String, code: Int32)
    case noGUISession
    case screenLocked
    case accessibilityNotTrusted
    case slackNotRunning
    case ambiguousSlack
    case slackWindowUnavailable
    case slackNotReady
    case treeUnavailable
    case uiDrift(locator: String, found: Int)
    case ambiguousWindow
    case uiBlocked
    case destinationMismatch(expected: Destination, actual: ClientLocation)
    case destinationUnreachable
    case slackInUse
    case busy
    case unsafeText(reason: String)
    case draftConflict(existingLength: Int)
    case writeFailed(draftLeft: Bool)
    case writeUnverified(draftLeft: Bool)
    case sendNotPerformed(draftLeft: Bool)
    case sendUnconfirmed
    case timeout

    public var code: String {
        switch self {
        case .internalError: return "internal"
        case .axFailure: return "ax_failure"
        case .noGUISession: return "no_gui_session"
        case .screenLocked: return "screen_locked"
        case .accessibilityNotTrusted: return "accessibility_not_trusted"
        case .slackNotRunning: return "slack_not_running"
        case .ambiguousSlack: return "ambiguous_slack"
        case .slackWindowUnavailable: return "slack_window_unavailable"
        case .slackNotReady: return "slack_not_ready"
        case .treeUnavailable: return "tree_unavailable"
        case .uiDrift: return "ui_drift"
        case .ambiguousWindow: return "ambiguous_window"
        case .uiBlocked: return "ui_blocked"
        case .destinationMismatch: return "destination_mismatch"
        case .destinationUnreachable: return "destination_unreachable"
        case .slackInUse: return "slack_in_use"
        case .busy: return "busy"
        case .unsafeText: return "unsafe_text"
        case .draftConflict: return "draft_conflict"
        case .writeFailed: return "write_failed"
        case .writeUnverified: return "write_unverified"
        case .sendNotPerformed: return "send_not_performed"
        case .sendUnconfirmed: return "send_unconfirmed"
        case .timeout: return "timeout"
        }
    }

    public var exitStatus: Int32 {
        switch self {
        case .internalError, .axFailure: return 1
        case .noGUISession, .screenLocked, .accessibilityNotTrusted: return 10
        case .slackNotRunning, .ambiguousSlack, .slackWindowUnavailable, .slackNotReady, .treeUnavailable: return 11
        case .uiDrift, .ambiguousWindow, .uiBlocked: return 12
        case .destinationMismatch, .destinationUnreachable: return 13
        case .slackInUse, .busy: return 14
        case .unsafeText, .draftConflict: return 15
        case .writeFailed, .writeUnverified, .sendNotPerformed: return 16
        case .sendUnconfirmed: return 17
        case .timeout: return 18
        }
    }

    public var message: String {
        switch self {
        case .internalError: return "An internal operation failed."
        case .axFailure: return "A macOS Accessibility operation failed."
        case .noGUISession: return "Run slack-remote inside the user's macOS login session."
        case .screenLocked: return "The screen is locked."
        case .accessibilityNotTrusted:
            return "Enable the app that launched slack-remote in System Settings › Privacy & Security › Accessibility."
        case .slackNotRunning: return "Slack is not running or has not finished launching."
        case .ambiguousSlack: return "More than one Slack process is running."
        case .slackWindowUnavailable: return "Slack is hidden or its client window is minimized."
        case .slackNotReady: return "Slack has no signed-in client window."
        case .treeUnavailable: return "Slack's Accessibility tree did not become available and settle in time."
        case .uiDrift: return "Slack's Accessibility tree did not match the expected structure."
        case .ambiguousWindow: return "Slack has more than one candidate client window."
        case .uiBlocked: return "A dialog is blocking the Slack window."
        case .destinationMismatch: return "Slack did not arrive at the requested conversation."
        case .destinationUnreachable:
            return "The requested conversation is not rendered in the sidebar. For a DM, try supplying --user."
        case .slackInUse: return "Slack is in the foreground and has recent user input. Use --interrupt to proceed."
        case .busy: return "Another slack-remote command is holding the lock."
        case .unsafeText: return "Slack remote refused the supplied text."
        case .draftConflict: return "The composer already contains different content."
        case .writeFailed: return "Slack did not apply the requested composer change."
        case .writeUnverified: return "Slack's composer change could not be verified."
        case .sendNotPerformed: return "Slack did not complete the send."
        case .sendUnconfirmed: return "The message may have been sent. Check the conversation before retrying."
        case .timeout: return "The command deadline passed."
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
        case .axFailure(let operation, let code): return ["operation": .string(operation), "code": .integer(Int(code))]
        case .uiDrift(let locator, let found): return ["locator": .string(locator), "found": .integer(found)]
        case .destinationMismatch(let expected, let actual):
            return [
                "expectedTeam": .string(expected.team.rawValue),
                "expectedConversation": .string(expected.conversation.rawValue),
                "actual": .string(actual.diagnosticDescription),
            ]
        case .unsafeText(let reason): return ["reason": .string(reason)]
        case .draftConflict(let existingLength): return ["existingLength": .integer(existingLength)]
        case .writeFailed(let draftLeft), .writeUnverified(let draftLeft), .sendNotPerformed(let draftLeft):
            return ["draftLeft": .boolean(draftLeft)]
        default: return nil
        }
    }
}
