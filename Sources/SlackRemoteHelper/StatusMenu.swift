import AppKit
import ServiceManagement
import SlackRemoteCore

final class StatusMenu: NSObject, NSMenuDelegate {
    private let server: HelperServer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let login = SMAppService.mainApp
    private let menu = NSMenu()

    init(server: HelperServer) {
        self.server = server
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right",
                                            accessibilityDescription: "SlackRemote")
        menu.delegate = self
        statusItem.menu = menu

        let defaults = UserDefaults.standard
        let launchedKey = "hasLaunched"
        if !defaults.bool(forKey: launchedKey) {
            if login.status == .notRegistered { setOpenAtLogin(true) }
            defaults.set(true, forKey: launchedKey)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = Environment.isAccessibilityTrusted()
        let slackRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: SlackApp.bundleIdentifier).isEmpty
        addStatus(trusted ? "Accessibility: Granted" : "Accessibility: Not granted")
        addStatus(slackRunning ? "Slack: Running" : "Slack: Not running")
        if let command = server.lastCommand {
            let time = DateFormatter.localizedString(from: command.time, dateStyle: .none, timeStyle: .short)
            addStatus("Last command: \(command.name) · exit \(command.status) · \(time)")
        } else {
            addStatus("Last command: none")
        }
        menu.addItem(.separator())
        if !trusted {
            addAction("Grant Access…", action: #selector(grantAccess))
        }
        let loginItem = addAction("Open at Login", action: #selector(toggleOpenAtLogin))
        loginItem.state = isOpenAtLogin ? .on : .off
        let quit = menu.addItem(withTitle: "Quit SlackRemote", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        quit.target = NSApp
    }

    private func addStatus(_ title: String) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
    }

    @discardableResult
    private func addAction(_ title: String, action: Selector) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func grantAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Environment.requestAccessibilityTrust(until: Date().addingTimeInterval(120))
        }
    }

    private var isOpenAtLogin: Bool { login.status == .enabled || login.status == .requiresApproval }

    @objc private func toggleOpenAtLogin() {
        setOpenAtLogin(!isOpenAtLogin)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try login.register() }
            else { try login.unregister() }
        } catch {
            NSLog("SlackRemote could not update Open at Login: %@", error.localizedDescription)
        }
    }
}
