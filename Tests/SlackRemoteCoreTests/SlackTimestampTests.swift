import SlackRemoteCore
import Testing

struct SlackTimestampTests {
    @Test(arguments: [
        ("1700000000.000100", true),
        ("170000000.000100", false),
        ("1700000000.00010", false),
        ("1700000000x000100", false),
        ("1700000000.000100\n", false),
    ])
    func validatesWholeTimestamp(_ value: String, expected: Bool) {
        #expect(SlackTimestamp.isValid(value) == expected)
    }
}
