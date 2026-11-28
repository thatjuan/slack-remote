import Foundation
import SlackRemoteCore
import WebKit

struct LocalConfig: Decodable, Sendable {
    struct Team: Decodable, Sendable {
        let id: String
        let name: String
        let url: String
        let token: String?
        let userID: String

        enum CodingKeys: String, CodingKey {
            case id, name, url, token
            case userID = "user_id"
        }
    }

    let teams: [String: Team]

    @MainActor
    static func read(from webView: WKWebView?) async throws -> Self {
        guard let json = try await webView?.callAsyncJavaScript(
            "return localStorage.getItem('localConfig_v2')",
            arguments: [:], in: nil, contentWorld: .defaultClient
        ) as? String else { throw SlackSessionError.missingConfig }
        return try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

/// One signed-in Slack browser profile. Its web view stays out of any window.
@MainActor
final class SlackSession: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    var dataStore: WKWebsiteDataStore? { webView?.configuration.websiteDataStore }

    private var pending: (navigation: WKNavigation, completion: CheckedContinuation<Void, Error>)?
    private var loading: Task<Void, Error>?
    private var refreshing: (team: TeamID, task: Task<Bool, Never>)?
    private var ready = false

    convenience init(storeID: UUID) {
        self.init(dataStore: WKWebsiteDataStore(forIdentifier: storeID))
    }

    init(dataStore: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SafariUserAgent.current
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    private func loadIdle() async throws {
        try await load { browser in
            browser.loadHTMLString("<!doctype html><title>slack-remote</title>",
                                   baseURL: URL(string: "https://app.slack.com/")!)
        }
    }

    private func loadClient(for team: TeamID, deadline: ContinuousClock.Instant) async throws {
        try await load(until: deadline) { browser in
            browser.load(URLRequest(url: URL(string: "https://app.slack.com/client/\(team.rawValue)")!))
        }
    }

    func localConfig() async throws -> LocalConfig {
        guard let webView else { throw SlackSessionError.navigationFailed }
        return try await LocalConfig.read(from: webView)
    }

    /// Share the initial navigation among concurrent commands for this profile.
    func prepare() async throws {
        while let refreshing { _ = await refreshing.task.value }
        if let loading { return try await loading.value }
        guard !ready else { return }
        let task = Task {
            defer { loading = nil }
            try await loadIdle()
            ready = true
        }
        loading = task
        try await task.value
    }

    /// Give Slack's full client up to twenty seconds to recover the team's token.
    func refresh(for team: TeamID) async -> Bool {
        while let refreshing {
            let recovered = await refreshing.task.value
            if refreshing.team == team { return recovered }
        }
        guard webView != nil else { return false }
        let task = Task {
            defer { refreshing = nil }
            if let loading { _ = try? await loading.value }
            ready = false
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(20)
            var recovered = false
            do {
                try await loadClient(for: team, deadline: deadline)
                while !Task.isCancelled, clock.now < deadline {
                    if let token = try? await localConfig().teams[team.rawValue]?.token, !token.isEmpty {
                        recovered = true
                        break
                    }
                    try await Task.sleep(until: min(deadline, clock.now + .milliseconds(500)), clock: clock)
                }
            } catch {}
            do {
                try await loadIdle()
                ready = true
                return recovered
            } catch {
                return false
            }
        }
        refreshing = (team, task)
        return await task.value
    }

    /// Release the browser before its persistent data store is removed.
    func close() {
        loading?.cancel()
        refreshing?.task.cancel()
        if let pending { finish(pending.navigation, result: .failure(SlackSessionError.navigationFailed)) }
        webView?.stopLoading()
        webView = nil
        ready = false
    }

    private func load(until deadline: ContinuousClock.Instant = .now + .seconds(25),
                      _ start: (WKWebView) -> WKNavigation?) async throws {
        try Task.checkCancellation()
        guard pending == nil, let navigation = webView.flatMap(start) else {
            throw SlackSessionError.navigationFailed
        }
        let timeout = Task { [weak self] in
            try await Task.sleep(until: deadline, clock: .continuous)
            self?.finish(navigation, result: .failure(SlackSessionError.navigationFailed))
            self?.webView?.stopLoading()
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { pending = (navigation, $0) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(navigation, result: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(navigation, result: .failure(SlackSessionError.navigationFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(navigation, result: .failure(SlackSessionError.navigationFailed))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        if let pending { finish(pending.navigation, result: .failure(SlackSessionError.navigationFailed)) }
    }

    private func finish(_ navigation: WKNavigation?, result: Result<Void, Error>) {
        guard let pending, pending.navigation === navigation else { return }
        self.pending = nil
        pending.completion.resume(with: result)
    }
}
