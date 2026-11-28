import AppKit
import ServiceManagement
import SlackRemoteCore
import SlackRemoteWeb

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    static let hasLaunchedKey = "hasLaunched"

    private let server: HelperServer
    private var pool: SessionPool?
    private var isReady = false
    private var signIn: SignInWindowController?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let login = SMAppService.mainApp
    private let menu = NSMenu()

    init(server: HelperServer, pool: SessionPool?, engine: Engine) {
        self.server = server
        self.pool = pool
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right",
                                            accessibilityDescription: "SlackRemote")
        menu.delegate = self
        statusItem.menu = menu

        let defaults = UserDefaults.standard
        let firstLaunch = defaults.object(forKey: Self.hasLaunchedKey) == nil
        if firstLaunch {
            if login.status == .notRegistered { setOpenAtLogin(true) }
            defaults.set(true, forKey: Self.hasLaunchedKey)
        }
        rebuild()
        pool?.onChange = { [weak self] in self?.rebuild() }
        Task { [weak self] in
            do {
                try await engine.waitUntilReady()
                self?.isReady = true
                self?.rebuild()
                if firstLaunch, pool?.records.isEmpty == true { _ = self?.openSignIn(.newAccount) }
            } catch {
                self?.pool = nil
                self?.rebuild()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if let pool {
            if !isReady {
                addStatus("Loading Slack accounts…", to: menu)
            } else if pool.records.isEmpty {
                addStatus("No Slack accounts", to: menu)
            } else {
                for account in pool.records { addAccountRow(account) }
            }
        } else {
            addStatus("Accounts file unreadable", to: menu)
        }
        menu.addItem(.separator())
        let add = addAction("Add Slack Account…", action: #selector(chooseSignIn), to: menu)
        add.representedObject = SignInPurpose.newAccount
        add.isEnabled = pool != nil && isReady
        menu.addItem(.separator())
        if let command = server.lastCommand {
            let time = DateFormatter.localizedString(from: command.time, dateStyle: .none, timeStyle: .short)
            addStatus("Last command: \(command.name) · exit \(command.status) · \(time)", to: menu)
        } else {
            addStatus("Last command: none", to: menu)
        }
        let loginItem = addAction("Open at Login", action: #selector(toggleOpenAtLogin), to: menu)
        loginItem.state = isOpenAtLogin ? .on : .off
        let quit = menu.addItem(withTitle: "Quit SlackRemote", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q")
        quit.target = NSApp
    }

    private func addAccountRow(_ account: AccountRecord) {
        guard let first = account.teams.first else { return }
        let names = account.teams.map(\.name).joined(separator: ", ")
        if account.state == .signedOut {
            let item = addAction("⚠ \(names) — Sign In Again…", action: #selector(chooseSignIn), to: menu)
            item.representedObject = SignInPurpose.signInAgain(account.id, first.id)
            return
        }
        let row = menu.addItem(withTitle: "\(names) — \(first.userName)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for team in account.teams { addStatus(team.name, to: submenu) }
        submenu.addItem(.separator())
        let add = addAction("Add Workspace…", action: #selector(chooseSignIn), to: submenu)
        add.representedObject = SignInPurpose.addWorkspace(account.id)
        let remove = addAction("Remove Account…", action: #selector(removeAccount), to: submenu)
        remove.representedObject = account.id
        row.submenu = submenu
    }

    @objc private func chooseSignIn(_ sender: NSMenuItem) {
        if let purpose = sender.representedObject as? SignInPurpose { _ = openSignIn(purpose) }
    }

    private func openSignIn(_ purpose: SignInPurpose) -> SignInWindowController? {
        guard let pool else { return nil }
        if signIn == nil {
            signIn = SignInWindowController(purpose: purpose, pool: pool) { [weak self] in
                self?.signIn = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
        guard let signIn else { return nil }
        NSApp.setActivationPolicy(.regular)
        // Wait for the status menu to finish closing before requesting activation.
        DispatchQueue.main.async { [weak self] in
            guard let signIn = self?.signIn else { return }
            signIn.open()
            if !NSApp.isActive {
                // Reopening the running app lets Launch Services activate its key window.
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
            }
        }
        return signIn
    }

    /// Open the account sign-in window and optionally wait for its account record.
    func addAccount(wait: Bool, deadline: Date) async throws -> [TeamID]? {
        guard Date() < deadline else { throw RemoteError.timeout }
        guard let pool, signIn?.isAddingAccount != false, let window = openSignIn(.newAccount) else {
            throw RemoteError.sessionUnavailable
        }
        guard wait else { return nil }
        while true {
            try Task.checkCancellation()
            if let account = pool.records.first(where: { $0.id == window.accountID }) {
                return account.teams.map(\.id)
            }
            guard signIn === window else { throw RemoteError.signInCancelled }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw RemoteError.timeout }
            try await Task.sleep(for: .seconds(min(remaining, 0.15)))
        }
    }

    @objc private func removeAccount(_ sender: NSMenuItem) {
        guard let pool, let id = sender.representedObject as? AccountID,
              let record = pool.records.first(where: { $0.id == id }) else { return }
        let names = record.teams.map(\.name).joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "Remove \(names)?"
        alert.informativeText = "SlackRemote signs out of these workspaces on this Mac."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do { try await removeAccount(id) }
            catch {
                let feedback = NSAlert()
                feedback.messageText = "SlackRemote could not finish removing this account."
                feedback.runModal()
            }
        }
    }

    /// Remove an account through the same profile cleanup used by the menu.
    func removeAccount(_ id: AccountID) async throws {
        guard let pool, pool.records.contains(where: { $0.id == id }) else {
            throw RemoteError.noAccount(team: nil)
        }
        if signIn?.accountID == id { signIn?.close() }
        try await pool.remove(id)
    }

    private func addStatus(_ title: String, to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
    }

    @discardableResult
    private func addAction(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
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
