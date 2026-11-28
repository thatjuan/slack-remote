/// Validates the timestamp format Slack uses to identify messages.
public enum SlackTimestamp {
    public static func isValid(_ value: String) -> Bool {
        value.wholeMatch(of: #/[0-9]{10}\.[0-9]{6}/#) != nil
    }
}
