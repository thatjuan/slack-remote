import Foundation

/// The user agent Safari on this Mac sends. Safari reports 10_15_7 on every macOS release since 11.
enum SafariUserAgent {
    static let current: String = {
        let safari = Bundle(path: "/Applications/Safari.app")
        return make(safariVersion: safari?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }()

    static func make(safariVersion: String?) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion ?? "18.0") Safari/605.1.15"
    }
}
