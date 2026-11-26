import Foundation
import WebKit

struct TransportResponse: Sendable {
    let status: Int
    let retryAfter: Double?
    let body: Data
}

enum TransportError: Error {
    case unknownTeam, pageFetchFailed, invalidResponse
}

@MainActor
func pagePost(_ session: SlackSession, team: String, method: String, params: [String: String])
    async throws -> TransportResponse {
    // Probe the route with a read-only method so falling back after CORS never repeats a write.
    if let endpoint = session.pageEndpoints[team] {
        return try await pageRequest(session, team: team, method: method, params: params, endpoint: endpoint)
    }
    for endpoint in ["", "https://app.slack.com/", "https://slack.com/"] {
        do {
            let probe = try await pageRequest(
                session, team: team, method: "auth.test", params: method == "auth.test" ? params : [:],
                endpoint: endpoint
            )
            session.pageEndpoints[team] = endpoint
            NSLog("SlackRemote PoC page API endpoint: %@", endpoint.isEmpty ? "workspace URL" : endpoint)
            if method == "auth.test" || probe.status == 429 { return probe }
        } catch TransportError.pageFetchFailed {
            continue
        }
        return try await pageRequest(session, team: team, method: method, params: params, endpoint: endpoint)
    }
    throw TransportError.pageFetchFailed
}

@MainActor
private func pageRequest(_ session: SlackSession, team: String, method: String, params: [String: String],
                         endpoint: String) async throws -> TransportResponse {
    let value = try await session.webView.callAsyncJavaScript(
        """
        const cfg = JSON.parse(localStorage.getItem('localConfig_v2'));
        const team = cfg?.teams?.[teamId];
        if (!team?.token) return { unknownTeam: true };
        const url = new URL('api/' + method, endpoint || team.url);
        if (url.protocol !== 'https:' ||
            !(url.hostname === 'slack.com' || url.hostname.endsWith('.slack.com'))) {
            return { unknownTeam: true };
        }
        const body = new URLSearchParams({ ...params, token: team.token });
        try {
            const r = await fetch(url, { method: 'POST', body, credentials: 'include', redirect: 'error' });
            return { status: r.status, retryAfter: r.headers.get('Retry-After'), body: await r.text() };
        } catch {
            return { fetchFailed: true };
        }
        """,
        arguments: ["teamId": team, "method": method, "params": params, "endpoint": endpoint],
        in: nil, contentWorld: .defaultClient
    )
    guard let result = value as? [String: Any] else { throw TransportError.invalidResponse }
    if result["unknownTeam"] as? Bool == true { throw TransportError.unknownTeam }
    if result["fetchFailed"] as? Bool == true { throw TransportError.pageFetchFailed }
    guard let status = result["status"] as? Int, let body = result["body"] as? String else {
        throw TransportError.invalidResponse
    }
    return TransportResponse(status: status, retryAfter: (result["retryAfter"] as? String).flatMap(Double.init),
                             body: Data(body.utf8))
}

@MainActor
func nativePost(_ session: SlackSession, team: String, method: String, params: [String: String])
    async throws -> TransportResponse {
    let config = try await session.localConfig()
    guard let workspace = config.teams[team], let base = URL(string: workspace.url),
          let url = URL(string: "api/" + method, relativeTo: base)?.absoluteURL,
          url.scheme == "https", let host = url.host,
          host == "slack.com" || host.hasSuffix(".slack.com") else {
        throw TransportError.unknownTeam
    }

    let cookies = await session.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    let requestCookies = cookies.filter { cookie in
        let domain = cookie.domain.lowercased()
        let bareDomain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard bareDomain == "slack.com" || bareDomain.hasSuffix(".slack.com"),
              cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
        let path = cookie.path.hasSuffix("/") ? cookie.path : cookie.path + "/"
        return (host == bareDomain || (domain.hasPrefix(".") && host.hasSuffix(domain)))
            && (url.path == cookie.path || url.path.hasPrefix(path))
    }

    var form = params
    form["token"] = workspace.token
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(SafariUserAgent.current, forHTTPHeaderField: "User-Agent")
    for (header, value) in HTTPCookie.requestHeaderFields(with: requestCookies) {
        request.setValue(value, forHTTPHeaderField: header)
    }
    request.httpBody = Data(form.map { formEncode($0.key) + "=" + formEncode($0.value) }.joined(separator: "&").utf8)

    let settings = URLSessionConfiguration.ephemeral
    settings.httpCookieStorage = nil
    settings.urlCache = nil
    let network = URLSession(configuration: settings, delegate: RejectRedirects(), delegateQueue: nil)
    defer { network.finishTasksAndInvalidate() }
    let (body, response) = try await network.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw TransportError.invalidResponse }
    return TransportResponse(status: http.statusCode,
                             retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init),
                             body: body)
}

private func formEncode(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
    return value.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+")
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
