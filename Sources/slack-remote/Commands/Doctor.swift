import ArgumentParser
import Foundation
import SlackRemoteCore

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check the Slack and macOS prerequisites.")

    @OptionGroup var options: CommandOptions

    @Flag(help: "Ask macOS for Accessibility access, open System Settings and wait up to 120 seconds for it.")
    var grant = false

    private static let grantWait: TimeInterval = 120

    private struct Check: Encodable {
        let name: String
        let ok: Bool
        let detail: String?
    }

    private struct Report: Encodable {
        static let names = ["helper", "gui_session", "screen_unlocked", "accessibility_trusted", "slack_running",
                            "slack_visible", "tree_available", "client_window", "locators"]

        private var results: [String: Check] = [:]
        private(set) var firstError: RemoteError?

        var checks: [Check] {
            let checks = Self.names.map { results[$0] ?? Check(name: $0, ok: false, detail: "prerequisite failed") }
            return checks + [results["tree_restored"]].compactMap { $0 }
        }

        mutating func check<T>(_ name: String, work: () throws -> T) -> T? {
            do {
                let result = try work()
                pass(name)
                return result
            } catch {
                fail(name, error: error)
                return nil
            }
        }

        mutating func pass(_ name: String, detail: String? = nil) {
            results[name] = Check(name: name, ok: true, detail: detail)
        }

        mutating func fail(_ name: String, error: any Error, detail: String? = nil) {
            let reason = CommandSupport.remoteError(error)
            if firstError == nil { firstError = reason }
            results[name] = Check(name: name, ok: false, detail: detail ?? reason.code)
        }

        func encode(to encoder: Encoder) throws {
            var result = encoder.container(keyedBy: CodingKeys.self)
            try result.encode(checks, forKey: .checks)
        }

        private enum CodingKeys: CodingKey { case checks }
    }

    func run() throws {
        var report = Report()
        let helperDetail = ProcessInfo.processInfo.environment["SLACK_REMOTE_VIA_HELPER"]
            .map { "via SlackRemote.app \($0)" } ?? "not used: \(HelperClient.unusedReason.rawValue)"
        report.pass("helper", detail: helperDetail)
        if let session = report.check("gui_session", work: Environment.guiSession) {
            _ = report.check("screen_unlocked") { try Environment.requireUnlocked(session) }
        }
        let host = HostApp.current()
        let guiChecksPassed = report.firstError == nil
        do {
            if grant && guiChecksPassed {
                guard Environment.requestAccessibilityTrust(until: Date().addingTimeInterval(Self.grantWait)) else {
                    throw RemoteError.accessibilityNotTrusted(host: host)
                }
            } else {
                try Environment.requireAccessibilityTrust()
            }
            report.pass("accessibility_trusted", detail: host?.name)
        } catch {
            report.fail("accessibility_trusted", error: error)
        }

        let deadline = Date().addingTimeInterval(options.timeout)

        var app: SlackApp?
        if report.firstError == nil, let running = report.check("slack_running", work: SlackApp.requireRunning) {
            _ = report.check("slack_visible") { try SlackApp.requireVisible(running) }
            if report.firstError == nil {
                var treeWasAvailable = false
                do {
                    let slack = try SlackApp(running: running)
                    app = slack
                    try CommandLock.acquire(deadline: deadline)
                    try slack.withTree(deadline: deadline) { tree in
                        treeWasAvailable = true
                        report.pass("tree_available", detail: CommandSupport.treeDetail(tree))
                        if options.debug { CommandSupport.debugTree(tree) }
                        if let client = report.check("client_window", work: { try SlackWindow.currentWindow(in: tree) }) {
                            checkLocators(in: client, report: &report)
                        }
                    }
                } catch {
                    report.fail(treeWasAvailable ? "tree_restored" : "tree_available", error: error)
                }
            }
        }

        if let error = report.firstError {
            try CommandSupport.fail("doctor", error: error, app: app, result: report)
        }
        try CommandSupport.succeed("doctor", app: app, result: report)
    }

    private func checkLocators(in client: ClientWindow, report: inout Report) {
        guard case .conversation = client.location else {
            report.pass("locators", detail: "not a conversation view")
            return
        }
        let primary = client.window.all(Locators.primaryView)
        let counts = [(Locators.webArea, client.window.all(Locators.webArea).count), (Locators.primaryView, primary.count)]
            + [Locators.composerEditor, Locators.sendButton, Locators.messageList].map { locator in
                (locator, primary.reduce(0) { $0 + $1.all(locator).count })
            }
        let detail = counts.map { "\($0.name)=\($1)" }.joined(separator: " ")
        if options.debug { CommandSupport.debug(detail) }
        if let (locator, found) = counts.first(where: { $0.1 != 1 }) {
            report.fail("locators", error: RemoteError.uiDrift(locator: locator.name, found: found), detail: detail)
        } else {
            report.pass("locators", detail: detail)
        }
    }
}
