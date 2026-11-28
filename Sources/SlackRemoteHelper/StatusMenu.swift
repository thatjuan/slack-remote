import AppKit
import ServiceManagement
import SlackRemoteCore
import SlackRemoteWeb

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let hasLaunchedKey = "hasLaunched"

    private let server: HelperServer
    private let webKit: WebKitPoC
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let login = SMAppService.mainApp
    private let menu = NSMenu()

    init(server: HelperServer, webKit: WebKitPoC) {
        self.server = server
        self.webKit = webKit
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right",
                                            accessibilityDescription: "SlackRemote")
        menu.delegate = self
        statusItem.menu = menu

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.hasLaunchedKey) {
            if login.status == .notRegistered { setOpenAtLogin(true) }
            defaults.set(true, forKey: Self.hasLaunchedKey)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        if let command = server.lastCommand {
            let time = DateFormatter.localizedString(from: command.time, dateStyle: .none, timeStyle: .short)
            addStatus("Last command: \(command.name) · exit \(command.status) · \(time)")
        } else {
            addStatus("Last command: none")
        }
        menu.addItem(.separator())
        addAction("Add Slack Account (PoC)…", action: #selector(addAccount))
        for title in webKit.teamTitles { addStatus(title) }
        menu.addItem(.separator())
        let loginItem = addAction("Open at Login", action: #selector(toggleOpenAtLogin))
        loginItem.state = isOpenAtLogin ? .on : .off
        let quit = menu.addItem(withTitle: "Quit SlackRemote", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        quit.target = NSApp
    }

    @objc private func addAccount() {
        webKit.addAccount()
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
