import Foundation
import SlackRemoteCore
import WebKit

enum SlackSessionError: Error {
    case missingConfig
    case navigationFailed
    case invalidResponse
}

/// Send a Slack API request using the token currently loaded in this WebKit profile.
@MainActor
func nativePost(_ team: LocalConfig.Team, in store: WKWebsiteDataStore, method: String, params: [String: String])
    async throws -> TransportResponse {
    guard let token = team.token, !token.isEmpty,
          method.wholeMatch(of: #/[a-zA-Z0-9._]+/#) != nil,
          let base = slackHTTPSURL(team.url), let host = base.host?.lowercased(),
          let url = URL(string: "/api/" + method, relativeTo: base)?.absoluteURL else {
        throw TransportFailure.notSent
    }

    let cookies = await store.httpCookieStore.allCookies().filter { cookie in
        let domain = cookie.domain.lowercased()
        let suffix = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let domainMatches = suffix == host || (domain.hasPrefix(".") && host.hasSuffix("." + suffix))
        let path = cookie.path
        let pathMatches = url.path == path || url.path.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        return domainMatches && pathMatches
    }
    var form = params
    form["token"] = token
    let request = makeNativePostRequest(url: url, form: form, cookies: cookies)
    try Task.checkCancellation()

    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    let network = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    defer { network.finishTasksAndInvalidate() }
    let (data, response): (Data, URLResponse)
    do { (data, response) = try await network.data(for: request) }
    catch {
        try Task.checkCancellation()
        throw TransportFailure.noResponse
    }
    guard let http = response as? HTTPURLResponse else { throw TransportFailure.noResponse }
    return TransportResponse(status: http.statusCode,
                             retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init), body: data)
}

func makeNativePostRequest(url: URL, form: [String: String], cookies: [HTTPCookie]) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = Data(form.sorted(by: { $0.key < $1.key }).map {
        "\(formEncode($0.key))=\(formEncode($0.value))"
    }.joined(separator: "&").utf8)
    request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue(SafariUserAgent.current, forHTTPHeaderField: "User-Agent")
    request.setValue(SafariUserAgent.acceptLanguage(Locale.preferredLanguages), forHTTPHeaderField: "Accept-Language")
    return request
}

/// Accept only HTTPS destinations on Slack's own domains.
func slackHTTPSURL(_ string: String) -> URL? {
    guard let url = URL(string: string), url.scheme == "https", url.user == nil, url.password == nil,
          let host = url.host?.lowercased(), host == "slack.com" || host.hasSuffix(".slack.com") else { return nil }
    return url
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
