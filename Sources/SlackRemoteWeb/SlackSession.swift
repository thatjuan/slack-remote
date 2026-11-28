import Foundation
import WebKit

struct LocalConfig: Decodable, Sendable {
    struct Team: Decodable, Sendable {
        let id: String
        let name: String
        let url: String
        let token: String
        let userID: String

        enum CodingKeys: String, CodingKey {
            case id, name, url, token
            case userID = "user_id"
        }
    }

    let teams: [String: Team]

    @MainActor
    static func read(from webView: WKWebView) async throws -> Self {
        guard let json = try await webView.callAsyncJavaScript(
            "return localStorage.getItem('localConfig_v2')",
            arguments: [:], in: nil, contentWorld: .defaultClient
        ) as? String else { throw WebKitPoCError.missingConfig }
        return try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

/// One signed-in Slack browser profile. Its web view stays out of any window.
@MainActor
final class SlackSession: NSObject, WKNavigationDelegate {
    let storeID: UUID
    let webView: WKWebView

    private var pending: (navigation: WKNavigation, completion: CheckedContinuation<Void, Error>)?
    private var loading: Task<Void, Error>?
    private var ready = false
    private(set) var prefersIdle = true

    init(storeID: UUID) {
        self.storeID = storeID
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SafariUserAgent.current
        #if DEBUG
        webView.isInspectable = true
        #endif
        super.init()
        webView.navigationDelegate = self
    }

    func loadIdle() async throws {
        try await load {
            webView.loadHTMLString("<!doctype html><title>slack-remote</title>",
                                   baseURL: URL(string: "https://app.slack.com/")!)
        }
    }

    func loadClient() async throws {
        try await load {
            webView.load(URLRequest(url: URL(string: "https://app.slack.com/client")!))
        }
    }

    func localConfig() async throws -> LocalConfig {
        try await LocalConfig.read(from: webView)
    }

    /// Share the initial navigation among concurrent commands for this profile.
    func prepare() async throws {
        if let loading { return try await loading.value }
        guard !ready else { return }
        let task = Task {
            defer { loading = nil }
            if prefersIdle {
                do {
                    try await loadIdle()
                    guard try await !localConfig().teams.isEmpty else { throw WebKitPoCError.missingConfig }
                } catch {
                    prefersIdle = false
                    NSLog("SlackRemote PoC local configuration was unavailable in the idle document. Loading the full Slack client.")
                    try await loadClient()
                }
            } else {
                try await loadClient()
            }
            ready = true
        }
        loading = task
        try await task.value
    }

    func useFullClient() async throws {
        if prefersIdle {
            prefersIdle = false
            ready = false
            NSLog("SlackRemote PoC page transport was blocked in the idle document. Loading the full Slack client.")
        }
        try await prepare()
    }

    private func load(_ start: () -> WKNavigation?) async throws {
        guard pending == nil, let navigation = start() else { throw WebKitPoCError.navigationFailed }
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(25))
            self?.finish(navigation, result: .failure(WebKitPoCError.navigationFailed))
            self?.webView.stopLoading()
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { pending = (navigation, $0) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(navigation, result: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(navigation, result: .failure(WebKitPoCError.navigationFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(navigation, result: .failure(WebKitPoCError.navigationFailed))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        if let pending { finish(pending.navigation, result: .failure(WebKitPoCError.navigationFailed)) }
    }

    private func finish(_ navigation: WKNavigation?, result: Result<Void, Error>) {
        guard let pending, pending.navigation === navigation else { return }
        self.pending = nil
        pending.completion.resume(with: result)
    }
}
