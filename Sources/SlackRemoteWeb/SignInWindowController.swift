import AppKit
import WebKit

@MainActor
final class SignInWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let storeID = UUID()
    private let finished: (AccountRecord?) -> Void
    private var popups: [ObjectIdentifier: NSWindow] = [:]
    private var polls: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var account: AccountRecord?

    init(finished: @escaping (AccountRecord?) -> Void) {
        self.finished = finished
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to Slack"
        window.contentView = webView
        window.center()
        super.init(window: window)
        window.delegate = self
        configure(webView)
        webView.load(URLRequest(url: URL(string: "https://slack.com/signin")!))
    }

    required init?(coder: NSCoder) { nil }

    func open() {
        showWindow(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func configure(_ webView: WKWebView) {
        webView.customUserAgent = SafariUserAgent.current
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
        -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, url.scheme == "https" || url.scheme == "about" else {
            let url = navigationAction.request.url
            NSLog("SlackRemote cancelled sign-in navigation (scheme: %@, host: %@)", url?.scheme ?? "", url?.host ?? "")
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let parent = webView.window else { return nil }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        configure(popup)
        let child = NSWindow(contentRect: parent.frame, styleMask: [.titled, .closable, .resizable],
                             backing: .buffered, defer: false)
        child.title = "Slack sign-in"
        child.isReleasedWhenClosed = false
        child.contentView = popup
        child.delegate = self
        popups[ObjectIdentifier(popup)] = child
        parent.addChildWindow(child, ordered: .above)
        child.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups[ObjectIdentifier(webView)]?.close()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let key = ObjectIdentifier(webView)
        polls.removeValue(forKey: key)?.cancel()
        guard Self.isClient(webView.url) else { return }
        polls[key] = Task { [weak self, weak webView] in
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(15)
            while !Task.isCancelled, clock.now < deadline,
                  let webView, Self.isClient(webView.url) {
                if let config = try? await LocalConfig.read(from: webView), !config.teams.isEmpty,
                   !Task.isCancelled, let self, self.account == nil {
                    self.account = AccountRecord(storeID: self.storeID, teams: config.teams.values.map(AccountRecord.Team.init)
                        .sorted { $0.id < $1.id })
                    self.close()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            for task in polls.values { task.cancel() }
            polls.removeAll()
            for child in Array(popups.values) { child.close() }
            finished(account)
        } else if let webView = closing.contentView as? WKWebView {
            let key = ObjectIdentifier(webView)
            polls.removeValue(forKey: key)?.cancel()
            closing.parent?.removeChildWindow(closing)
            popups.removeValue(forKey: key)
        }
    }

    private static func isClient(_ url: URL?) -> Bool {
        guard let url, url.host == "app.slack.com" else { return false }
        return url.path == "/client" || url.path.hasPrefix("/client/")
    }
}
