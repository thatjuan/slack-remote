import Foundation
import WebKit

struct LocalConfig: Decodable, Sendable {
    struct Team: Decodable, Sendable {
        let id: String
        let name: String
        let url: String
        let token: String
        let userID: String

        private enum CodingKeys: String, CodingKey {
            case id, name, url, token
            case userID = "user_id"
        }
    }

    let teams: [String: Team]
}

/// One signed-in browser profile. The helper keeps its web view offscreen for its lifetime.
@MainActor
final class SlackSession: NSObject, WKNavigationDelegate {
    static let origin = URL(string: "https://app.slack.com/")!

    let storeID: UUID
    let webView: WKWebView
    private(set) var isIdle = false
    var pageEndpoints: [String: String] = [:]

    private var loading: (navigation: WKNavigation, continuation: CheckedContinuation<Void, Error>)?
    private var clientLoad: Task<Void, Error>?

    init(storeID: UUID) {
        self.storeID = storeID
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        webView = Self.makeWebView(configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = SafariUserAgent.current
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func loadIdle() async throws {
        try await navigate {
            webView.loadHTMLString("<!doctype html><title>slack-remote</title>", baseURL: Self.origin)
        }
        isIdle = true
        clientLoad = nil
        pageEndpoints.removeAll()
    }

    func loadClient() async throws {
        if let clientLoad { return try await clientLoad.value }
        let task = Task {
            try await navigate {
                webView.load(URLRequest(url: Self.origin.appendingPathComponent("client")))
            }
            isIdle = false
            pageEndpoints.removeAll()
        }
        clientLoad = task
        do {
            try await task.value
        } catch {
            clientLoad = nil
            throw error
        }
    }

    func localConfig() async throws -> LocalConfig {
        try await Self.localConfig(in: webView)
    }

    static func localConfig(in webView: WKWebView) async throws -> LocalConfig {
        let value = try await webView.callAsyncJavaScript(
            "return localStorage.getItem('localConfig_v2')",
            arguments: [:], in: nil, contentWorld: .defaultClient
        )
        guard let json = value as? String else { throw SessionError.missingConfig }
        return try JSONDecoder().decode(LocalConfig.self, from: Data(json.utf8))
    }

    private func navigate(_ start: () -> WKNavigation?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard loading == nil, let navigation = start() else {
                continuation.resume(throwing: SessionError.navigationFailed)
                return
            }
            loading = (navigation, continuation)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(navigation, with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(navigation, with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(navigation, with: .failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let loading { finish(loading.navigation, with: .failure(SessionError.navigationFailed)) }
    }

    private func finish(_ navigation: WKNavigation?, with result: Result<Void, Error>) {
        guard let loading, loading.navigation === navigation else { return }
        self.loading = nil
        loading.continuation.resume(with: result)
    }

    private enum SessionError: Error {
        case missingConfig, navigationFailed
    }
}
