import AppKit
import WebKit

@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let session = SlackSession(storeID: UUID())
    private let window: NSWindow
    private let completed: (UUID, LocalConfig) -> Void
    private let closed: () -> Void
    private var popups: [WKWebView: NSWindow] = [:]
    private var poll: Task<Void, Never>?

    init(completed: @escaping (UUID, LocalConfig) -> Void, closed: @escaping () -> Void) {
        self.completed = completed
        self.closed = closed
        window = Self.makeWindow(title: "Sign in to Slack")
        super.init()
        window.delegate = self
        configure(session.webView, in: window)
        session.webView.load(URLRequest(url: URL(string: "https://slack.com/signin")!))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func configure(_ webView: WKWebView, in window: NSWindow) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.contentView = webView
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""
        guard scheme == "https" || scheme == "about" else {
            NSLog("SlackRemote PoC cancelled navigation scheme=%@ host=%@", scheme, url?.host ?? "")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = SlackSession.makeWebView(configuration: configuration)
        let child = Self.makeWindow(title: "Slack sign-in")
        child.delegate = self
        configure(popup, in: child)
        popups[popup] = child
        window.addChildWindow(child, ordered: .above)
        child.makeKeyAndOrderFront(nil)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups[webView]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === window {
            poll?.cancel()
            for child in Array(popups.values) { child.close() }
            closed()
        } else if let popup = popups.first(where: { $0.value === closing })?.key {
            window.removeChildWindow(closing)
            popups.removeValue(forKey: popup)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard Self.isClient(webView.url) else { return }
        poll?.cancel()
        poll = Task { [weak self, weak webView] in
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(15)
            while !Task.isCancelled, clock.now < deadline, let webView, Self.isClient(webView.url) {
                if let config = try? await SlackSession.localConfig(in: webView), !config.teams.isEmpty {
                    guard !Task.isCancelled, clock.now <= deadline, Self.isClient(webView.url), let self else {
                        return
                    }
                    let storeID = self.session.storeID
                    self.window.close()
                    self.completed(storeID, config)
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private static func isClient(_ url: URL?) -> Bool {
        guard let url, url.host == "app.slack.com" else { return false }
        return url.path == "/client" || url.path.hasPrefix("/client/")
    }
}
