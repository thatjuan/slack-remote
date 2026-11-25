import AppKit
import ApplicationServices
import CoreGraphics

public enum Environment {
    public struct GUISession {
        public let isLocked: Bool
    }

    public static func guiSession() throws -> GUISession {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session["kCGSSessionOnConsoleKey"] as? Bool == true else {
            throw RemoteError.noGUISession
        }
        return GUISession(isLocked: session["CGSSessionScreenIsLocked"] as? Bool == true)
    }

    public static func requireUnlocked(_ session: GUISession) throws {
        guard !session.isLocked else { throw RemoteError.screenLocked }
    }

    public static func requireAccessibilityTrust() throws {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([promptKey: false] as CFDictionary) else {
            throw RemoteError.accessibilityNotTrusted
        }
    }

    public static func secondsSinceUserInput() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    public static func requireSlackIdle(interrupt: Bool) throws {
        try requireSlackIdle(interrupt: interrupt,
                             frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                             secondsSinceUserInput: secondsSinceUserInput)
    }

    static func requireSlackIdle(interrupt: Bool, frontmostBundleID: String?,
                                 secondsSinceUserInput: () -> Double) throws {
        if !interrupt, frontmostBundleID == SlackApp.bundleIdentifier, secondsSinceUserInput() < 30 {
            throw RemoteError.slackInUse
        }
    }
}
