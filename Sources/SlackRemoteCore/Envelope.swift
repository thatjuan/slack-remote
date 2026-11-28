import Foundation

/// The CLI's JSON output, shared by local commands and the helper.
public enum Envelope {
    private struct Success<Output: Encodable>: Encodable {
        var ok = true
        let command: String
        let warnings: [String]
        let result: Output
    }

    private struct Failure<Output: Encodable>: Encodable {
        struct ErrorBody: Encodable {
            let code: String
            let message: String
            let details: [String: RemoteError.Detail]?
        }

        var ok = false
        let command: String
        let warnings: [String]?
        let result: Output?
        let error: ErrorBody
    }

    public static func success(_ command: String, result: some Encodable, warnings: [String] = []) throws -> Data {
        try encode(Success(command: command, warnings: warnings, result: result))
    }

    public static func failure(_ command: String, error: RemoteError, warnings: [String] = [],
                               result: (some Encodable)?) throws -> Data {
        let envelope = Failure(command: command, warnings: warnings.isEmpty ? nil : warnings, result: result,
                               error: .init(code: error.code, message: error.message, details: error.details))
        return try encode(envelope)
    }

    public static func writeFailure(_ command: String, error: RemoteError) throws {
        try FileHandle.standardError.write(contentsOf: failure(command, error: error, result: nil as Bool?))
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0a)
        return data
    }
}
