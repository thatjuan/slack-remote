import Foundation

/// Validates a visible, single-component name for a Slack upload.
public enum FileName {
    public static func validate(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"),
              !name.contains("\\"), name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw RemoteError.fileRejected(reason: "invalid_name")
        }
    }
}
