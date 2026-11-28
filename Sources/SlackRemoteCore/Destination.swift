import Foundation

public struct TeamID: Hashable, RawRepresentable, Codable, Sendable {
    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[TE][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }

    public init?(rawValue: String) { self.init(rawValue) }
}

public struct ConversationID: Hashable, RawRepresentable, Codable, Sendable {
    public enum Kind: String, Encodable { case channel, directMessage, group }

    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[CDG][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }

    public init?(rawValue: String) { self.init(rawValue) }

    public var kind: Kind {
        switch rawValue.first {
        case "C": return .channel
        case "D": return .directMessage
        default: return .group
        }
    }
}

public struct UserID: Hashable, RawRepresentable, Codable, Sendable {
    public let rawValue: String

    public init?(_ raw: String) {
        guard raw.range(of: #"\A[UW][A-Z0-9]{8,}\z"#, options: .regularExpression) != nil else { return nil }
        rawValue = raw
    }

    public init?(rawValue: String) { self.init(rawValue) }
}

public struct Destination: Hashable, Codable, Sendable {
    public let team: TeamID
    public let conversation: ConversationID

    public init(team: TeamID, conversation: ConversationID) {
        self.team = team
        self.conversation = conversation
    }
}
