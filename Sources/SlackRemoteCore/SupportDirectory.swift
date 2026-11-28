import Foundation

/// Locates the private directory shared by SlackRemote.app and the CLI.
public enum SupportDirectory {
    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/slack-remote", isDirectory: true)
    }
}
