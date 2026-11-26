import Foundation

/// The user agent Safari on this Mac sends. Safari reports 10_15_7 on macOS 11 and later.
enum SafariUserAgent {
    static var current: String {
        let plist = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        return make(safariVersion: plist?["CFBundleShortVersionString"] as? String)
    }

    static func make(safariVersion: String?) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion ?? "18.0") Safari/605.1.15"
    }
}
