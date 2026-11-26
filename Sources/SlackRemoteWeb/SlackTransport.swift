import Foundation
import WebKit

struct TransportResponse: Sendable {
    let status: Int
    let retryAfter: Double?
    let body: Data
}

@MainActor
func pagePost(_ session: SlackSession, team: String, method: String, params: [String: String]) async throws
    -> TransportResponse {
    let result = try await session.webView.callAsyncJavaScript("""
        const cfg = JSON.parse(localStorage.getItem('localConfig_v2'));
        const team = cfg?.teams?.[teamId];
        if (!team) return { missingTeam: true };
        const workspace = new URL(team.url);
        if (workspace.protocol !== 'https:' || workspace.username || workspace.password ||
            !(workspace.hostname === 'slack.com' || workspace.hostname.endsWith('.slack.com')))
            return { invalidURL: true };
        const body = new URLSearchParams({ ...params, token: team.token });
        for (const base of [workspace, 'https://app.slack.com/', 'https://slack.com/']) {
            const endpoint = new URL('api/' + method, base);
            let response;
            try {
                response = await fetch(endpoint, {
                    method: 'POST', body, credentials: 'include', redirect: 'error',
                    signal: AbortSignal.timeout(15000)
                });
            } catch (error) {
                if (error.name !== 'TypeError') return { networkError: true };
                continue;
            }
            return {
                status: response.status, retryAfter: response.headers.get('Retry-After'),
                body: await response.text(), fallbackHost: base === workspace ? '' : endpoint.hostname
            };
        }
        return { blocked: true };
        """, arguments: ["teamId": team, "method": method, "params": params], in: nil, contentWorld: .defaultClient)
    guard let result = result as? [String: Any] else { throw WebKitPoCError.invalidResponse }
    if result["missingTeam"] as? Bool == true { throw WebKitPoCError.missingConfig }
    if result["invalidURL"] as? Bool == true { throw WebKitPoCError.invalidWorkspaceURL }
    if result["networkError"] as? Bool == true { throw WebKitPoCError.networkFailed }
    if result["blocked"] as? Bool == true { throw WebKitPoCError.pageBlocked }
    guard let status = result["status"] as? Int, let body = result["body"] as? String else {
        throw WebKitPoCError.invalidResponse
    }
    if let fallback = result["fallbackHost"] as? String, !fallback.isEmpty {
        NSLog("SlackRemote PoC page transport used %@.", fallback)
    }
    return TransportResponse(status: status, retryAfter: (result["retryAfter"] as? String).flatMap(Double.init),
                             body: Data(body.utf8))
}

@MainActor
func nativePost(_ session: SlackSession, team: String, method: String, params: [String: String]) async throws
    -> TransportResponse {
    guard let team = try await session.localConfig().teams[team] else { throw WebKitPoCError.missingConfig }
    guard let base = URL(string: team.url), base.scheme == "https", base.user == nil, base.password == nil,
          let host = base.host?.lowercased(), host == "slack.com" || host.hasSuffix(".slack.com"),
          let url = URL(string: "api/" + method, relativeTo: base)?.absoluteURL else {
        throw WebKitPoCError.invalidWorkspaceURL
    }

    let cookies = await session.webView.configuration.websiteDataStore.httpCookieStore.allCookies().filter { cookie in
        let domain = cookie.domain.lowercased()
        let suffix = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let domainMatches = suffix == host || (domain.hasPrefix(".") && host.hasSuffix("." + suffix))
        let path = cookie.path
        let pathMatches = url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        return domainMatches && pathMatches
    }
    var form = params
    form["token"] = team.token
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = Data(form.sorted(by: { $0.key < $1.key }).map {
        "\(formEncode($0.key))=\(formEncode($0.value))"
    }.joined(separator: "&").utf8)
    request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(SafariUserAgent.current, forHTTPHeaderField: "User-Agent")

    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    let network = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    defer { network.finishTasksAndInvalidate() }
    let (data, response) = try await network.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw WebKitPoCError.invalidResponse }
    return TransportResponse(status: http.statusCode,
                             retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init), body: data)
}

private func formEncode(_ value: String) -> String {
    let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
    return value.addingPercentEncoding(withAllowedCharacters: unreserved)!
        .replacingOccurrences(of: "%20", with: "+")
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
