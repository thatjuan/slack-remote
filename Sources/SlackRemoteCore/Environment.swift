import AppKit
import ApplicationServices
import CoreGraphics

public enum Environment {
    public static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// The Settings path that holds the Accessibility list; macOS 27 renamed the pane.
    public static let accessibilitySettingsPath = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        ? "System Settings › Privacy & Security › Device Control and Data Access"
        : "System Settings › Privacy & Security › Accessibility"

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

    /// Check Accessibility trust without showing a prompt unless explicitly requested.
    public static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
    }

    public static func requireAccessibilityTrust() throws {
        guard isAccessibilityTrusted() else {
            throw RemoteError.accessibilityNotTrusted(host: HostApp.current())
        }
    }

    /// Prompt, open Accessibility settings and poll every half second until trusted or the deadline passes.
    public static func requestAccessibilityTrust(until deadline: Date) -> Bool {
        guard !isAccessibilityTrusted() else { return true }
        _ = isAccessibilityTrusted(prompt: true)
        if !NSWorkspace.shared.open(accessibilitySettingsURL) {
            let fallback = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
            NSWorkspace.shared.open(fallback)
        }
        while Date() < deadline {
            if isAccessibilityTrusted() { return true }
            let nextAttempt = min(deadline, Date().addingTimeInterval(0.5))
            while Date() < nextAttempt { Poll.wait(until: nextAttempt) }
        }
        return isAccessibilityTrusted()
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
