import Foundation

/// The user agent Safari on this Mac sends. Safari reports 10_15_7 on every macOS release since 11.
enum SafariUserAgent {
    static let current: String = {
        let safari = Bundle(path: "/Applications/Safari.app")
        return make(safariVersion: safari?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }()

    static func make(safariVersion: String?) -> String {
        let version = safariVersion ?? "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0"
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(version) Safari/605.1.15"
    }

    static func acceptLanguage(_ preferred: [String]) -> String {
        guard let first = preferred.first else { return "" }
        let language = Locale.Language(identifier: first)
        let secondary = language.region != nil ? language.languageCode?.identifier : preferred.dropFirst().first
        guard let secondary else { return first }
        return "\(first),\(secondary);q=0.9"
    }
}
