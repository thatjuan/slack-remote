import AppKit
import SlackRemoteCore
import WebKit

/// Selects the profile and Slack entry point for a sign-in window.
public enum SignInPurpose {
    case newAccount
    case addWorkspace(AccountID)
    case signInAgain(AccountID, TeamID)

    var accountID: AccountID? {
        switch self {
        case .newAccount: return nil
        case .addWorkspace(let id), .signInAgain(let id, _): return id
        }
    }

    var url: URL {
        if case .signInAgain(_, let team) = self {
            return URL(string: "https://app.slack.com/client/\(team.rawValue)")!
        }
        return URL(string: "https://slack.com/signin")!
    }
}

/// Runs sign-in in a WebKit profile and commits only verified workspace identities.
@MainActor
public final class SignInWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let pool: SessionPool
    private let id: AccountID
    private let finished: () -> Void
    private var purpose: SignInPurpose
    private var browser: SignInBrowserView?
    private var popups: [ObjectIdentifier: NSWindow] = [:]
    private var polls: [ObjectIdentifier: Task<Void, Never>] = [:]

    public var accountID: AccountID { id }
    public var isAddingAccount: Bool {
        if case .newAccount = purpose { return true }
        return false
    }

    public init?(purpose: SignInPurpose, pool: SessionPool, finished: @escaping () -> Void) {
        if let id = purpose.accountID, !pool.records.contains(where: { $0.id == id }) { return nil }
        self.pool = pool
        self.purpose = purpose
        self.id = purpose.accountID ?? AccountID()
        self.finished = finished
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 400, height: 560)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    private var record: AccountRecord? { pool.records.first { $0.id == id } }

    /// Repeated menu requests focus the existing sign-in or provider window.
    public func open() {
        if browser == nil {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id.rawValue)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            configure(webView)
            browser = SignInBrowserView(webView: webView, startURL: purpose.url)
            begin()
        }
        showWindow(nil)
        NSApp.activate()
        let front = popups.values.first ?? window
        front?.makeKeyAndOrderFront(nil)
        front?.orderFrontRegardless()
    }

    private func begin() {
        guard let browser, let window else { return }
        switch purpose {
        case .newAccount:
            window.title = "Add Slack Account"
        case .addWorkspace:
            window.title = "Add Workspace to \(record?.teams.first?.name ?? "Slack")"
        case .signInAgain(_, let team):
            window.title = "Sign In Again to \(record?.teams.first { $0.id == team }?.name ?? "Slack")"
        }
        window.defaultButtonCell = nil
        window.contentView = browser
        browser.showBanner(nil)
        browser.navigate(to: purpose.url)
    }

    private func configure(_ webView: WKWebView) {
        webView.customUserAgent = SafariUserAgent.current
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy {
        guard let scheme = navigationAction.request.url?.scheme, scheme == "https" || scheme == "about" else {
            return .cancel
        }
        return .allow
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url ?? URL(string: "about:blank")!
        guard let parent = webView.window, url.scheme == "https" || url.scheme == "about" else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        let child = NSWindow(contentRect: parent.contentRect(forFrameRect: parent.frame),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        child.title = "Slack Sign-In"
        child.isReleasedWhenClosed = false
        child.contentView = SignInBrowserView(webView: popup, startURL: url)
        child.delegate = self
        popups[ObjectIdentifier(popup)] = child
        parent.addChildWindow(child, ordered: .above)
        child.makeKeyAndOrderFront(nil)
        return popup
    }

    public func webViewDidClose(_ webView: WKWebView) {
        popups[ObjectIdentifier(webView)]?.close()
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        polls.removeValue(forKey: ObjectIdentifier(webView))?.cancel()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let key = ObjectIdentifier(webView)
        polls.removeValue(forKey: key)?.cancel()
        guard let url = webView.url, slackHTTPSURL(url.absoluteString) != nil else { return }
        let isClient = Self.isClient(url)
        let original = Set(record?.teams.map { $0.id.rawValue } ?? [])
        let purpose = self.purpose
        polls[key] = Task { [weak self, weak webView] in
            if !isClient {
                if let webView { await Self.followBrowserLink(in: webView, from: url) }
                return
            }
            guard let store = webView?.configuration.websiteDataStore else { return }
            let deadline = ContinuousClock.now + .seconds(15)
            var attemptedVerification = false
            while !Task.isCancelled, ContinuousClock.now < deadline, Self.isClient(webView?.url) {
                if let config = try? await LocalConfig.read(from: webView) {
                    switch purpose {
                    case .signInAgain(_, let team):
                        if let candidate = config.teams[team.rawValue], candidate.token?.isEmpty == false {
                            attemptedVerification = true
                            if let identity = try? await SignInAPI.identity(for: candidate, in: store), identity.ok,
                               let user = identity.user, !Task.isCancelled {
                                self?.completeSignInAgain(team: team, user: user)
                                return
                            }
                        }
                    case .newAccount, .addWorkspace:
                        let candidates = config.teams.values.filter { !original.contains($0.id) && $0.token?.isEmpty == false }
                        if !candidates.isEmpty {
                            attemptedVerification = true
                            let workspaces = await Self.verify(candidates, in: store)
                            guard !Task.isCancelled else { return }
                            if !workspaces.isEmpty {
                                self?.completeSignIn(workspaces)
                                return
                            }
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if attemptedVerification, !Task.isCancelled {
                self?.browser?.showBanner("SlackRemote could not verify this workspace. Reload to try again.")
            }
        }
    }

    /// Follow Slack's own browser continuation on the desktop-app interstitial.
    private static func followBrowserLink(in webView: WKWebView, from url: URL) async {
        let destination = try? await webView.callAsyncJavaScript(#"""
            const link = Array.from(document.links).find(({textContent}) =>
                /(?:use|open|continue|launch).{0,40}\b(?:in (?:your |the )?(?:web )?browser|on the web)\b/i
                    .test(textContent.trim().replace(/\s+/g, ' ')));
            return link?.href ?? null;
            """#, arguments: [:], in: nil, contentWorld: .defaultClient) as? String
        guard !Task.isCancelled, webView.url == url, let destination,
              let next = slackHTTPSURL(destination), next != url else { return }
        webView.load(URLRequest(url: next))
    }

    private static func isClient(_ url: URL?) -> Bool {
        guard let url, url.host == "app.slack.com" else { return false }
        return url.path == "/client" || url.path.hasPrefix("/client/")
    }

    private static func verify(_ candidates: [LocalConfig.Team], in store: WKWebsiteDataStore) async
        -> [AccountRecord.Team] {
        var verified: [AccountRecord.Team] = []
        for candidate in candidates.sorted(by: { $0.id < $1.id }) {
            guard !Task.isCancelled else { break }
            if let workspace = try? await SignInAPI.workspace(for: candidate, in: store) { verified.append(workspace) }
        }
        return verified
    }

    private func completeSignIn(_ workspaces: [AccountRecord.Team]) {
        var duplicates: [String] = []
        var added: [AccountRecord.Team] = []
        let current = record
        for workspace in workspaces {
            if let owner = pool.records.first(where: { $0.id != id && $0.teams.contains { $0.id == workspace.id } }),
               let existing = owner.teams.first(where: { $0.id == workspace.id }) {
                duplicates.append("\(existing.name) is already signed in as \(existing.userName) in another account. Remove it there first to sign in here.")
            } else if current?.teams.contains(where: { $0.id == workspace.id }) != true {
                added.append(workspace)
            }
        }
        let banner = duplicates.isEmpty ? nil : duplicates.joined(separator: "\n")
        guard !added.isEmpty else {
            browser?.showBanner(banner)
            return
        }
        do {
            if var current {
                current.teams.append(contentsOf: added)
                try pool.update(current)
            } else if let store = browser?.webView.configuration.websiteDataStore, case .newAccount = purpose {
                let account = AccountRecord(id: id, teams: added, state: .active, addedAt: Date())
                try pool.add(account, session: SlackSession(dataStore: store))
            } else {
                return
            }
            showSuccess(added, banner: banner)
        } catch {
            browser?.showBanner("SlackRemote could not save this account. Reload to try again.")
        }
    }

    private func completeSignInAgain(team: TeamID, user: UserID) {
        guard var record, let workspace = record.teams.first(where: { $0.id == team }) else { return }
        guard user == workspace.user else {
            browser?.showBanner("Signed in as a different user. Use Add Slack Account for a second identity.")
            return
        }
        record.state = .active
        do {
            try pool.update(record)
            showSuccess([workspace], banner: nil)
        } catch {
            browser?.showBanner("SlackRemote could not save this account. Reload to try again.")
        }
    }

    private func showSuccess(_ teams: [AccountRecord.Team], banner: String?) {
        guard let window else { return }
        cancelPolls()
        browser?.navigate(to: URL(string: "about:blank")!)
        let heading = NSTextField(labelWithString: "Signed in")
        heading.font = .systemFont(ofSize: 21, weight: .semibold)
        let checkmark = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill",
                                                  accessibilityDescription: nil)!)
        checkmark.contentTintColor = .systemGreen
        let title = NSStackView(views: [checkmark, heading])
        title.alignment = .centerY

        let rows = teams.map { team in
            let name = NSTextField(labelWithString: team.name)
            let user = NSTextField(labelWithString: team.userName)
            user.textColor = .secondaryLabelColor
            let row = NSStackView(views: [name, NSView(), user])
            row.alignment = .centerY
            return row
        }
        let table = NSStackView(views: rows)
        table.orientation = .vertical
        table.alignment = .leading
        table.spacing = 10

        let another = NSButton(title: "Add Another Workspace", target: self, action: #selector(addAnotherWorkspace))
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        let actions = NSStackView(views: [another, NSView(), done])
        let content = NSStackView(views: [title, table, actions])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 24
        if let banner { content.insertArrangedSubview(SignInBrowserView.banner(banner), at: 0) }

        let view = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            actions.widthAnchor.constraint(equalTo: content.widthAnchor),
            table.widthAnchor.constraint(equalTo: content.widthAnchor),
        ] + rows.map { $0.widthAnchor.constraint(equalTo: table.widthAnchor) })
        window.contentView = view
        window.defaultButtonCell = done.cell as? NSButtonCell
    }

    @objc private func addAnotherWorkspace() {
        purpose = .addWorkspace(id)
        begin()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure(in: webView, error: error)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFailure(in: webView, error: error)
    }

    private func showFailure(in webView: WKWebView, error: Error) {
        let error = error as NSError
        guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
        let retryURL = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if let retryURL, retryURL.scheme != "https" { return }
        (webView.window?.contentView as? SignInBrowserView)?.showFailure(retryURL: retryURL)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            cancelPolls()
            browser?.webView.stopLoading()
            closing.contentView = nil
            browser = nil
            if record == nil, case .newAccount = purpose {
                let store = id.rawValue
                Task {
                    do { try await SessionPool.removeStore(store) }
                    catch { NSLog("SlackRemote could not remove the abandoned sign-in profile.") }
                }
            }
            finished()
        } else if let browser = closing.contentView as? SignInBrowserView {
            let key = ObjectIdentifier(browser.webView)
            polls.removeValue(forKey: key)?.cancel()
            browser.webView.stopLoading()
            closing.parent?.removeChildWindow(closing)
            closing.contentView = nil
            popups.removeValue(forKey: key)
        }
    }

    private func cancelPolls() {
        for task in polls.values { task.cancel() }
        polls.removeAll()
        for child in Array(popups.values) { child.close() }
    }
}
