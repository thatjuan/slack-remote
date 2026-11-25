import Foundation

public struct TeamID: Hashable {
    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[TE][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }
}

public struct ConversationID: Hashable {
    public enum Kind: String, Encodable { case channel, directMessage, group }

    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[CDG][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }

    public var kind: Kind {
        switch rawValue.first {
        case "C": return .channel
        case "D": return .directMessage
        default: return .group
        }
    }
}

public struct UserID: Hashable {
    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[UW][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }
}

public struct Destination: Hashable {
    public let team: TeamID
    public let conversation: ConversationID

    public init(team: TeamID, conversation: ConversationID) {
        self.team = team
        self.conversation = conversation
    }

    public var channelLink: URL {
        // ID validation restricts both query values to ASCII letters and digits.
        URL(string: "slack://channel?team=\(team.rawValue)&id=\(conversation.rawValue)")!
    }

    public func userLink(_ user: UserID) -> URL {
        URL(string: "slack://user?team=\(team.rawValue)&id=\(user.rawValue)")!
    }
}

public enum ClientLocation: Equatable {
    case conversation(Destination, trailing: [String])
    case other(team: TeamID, path: [String])
    case notClient

    public static func parse(url: String) -> ClientLocation {
        guard let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "app.slack.com" else { return .notClient }

        let segments = components.percentEncodedPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments[0] == "client", let team = TeamID(String(segments[1])) else {
            return .notClient
        }
        let path = segments.dropFirst(2).map { String($0) }
        if let first = path.first, let conversation = ConversationID(first) {
            return .conversation(Destination(team: team, conversation: conversation), trailing: Array(path.dropFirst()))
        }
        return .other(team: team, path: path == [""] ? [] : path)
    }

    public var team: TeamID? {
        switch self {
        case .conversation(let destination, _): return destination.team
        case .other(let team, _): return team
        case .notClient: return nil
        }
    }

    public var destination: Destination? {
        guard case .conversation(let destination, _) = self else { return nil }
        return destination
    }

    // Omit path segments, which can include user-entered search text.
    var diagnosticDescription: String {
        switch self {
        case .conversation(let destination, _):
            return "conversation \(destination.team.rawValue)/\(destination.conversation.rawValue)"
        case .other(let team, _): return "other \(team.rawValue)"
        case .notClient: return "no client location"
        }
    }
}
