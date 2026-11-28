import Foundation

public enum HelperProtocol {
    public static let version = 2
    public static var socketURL: URL { SupportDirectory.url.appendingPathComponent("helper.sock") }

    public struct Request: Codable, Equatable, Sendable {
        public let protocolVersion: Int
        public let clientVersion: String
        public let arguments: [String]
        public let passesFile: Bool

        public init(protocolVersion: Int = HelperProtocol.version, clientVersion: String,
                    arguments: [String], passesFile: Bool = false) {
            self.protocolVersion = protocolVersion
            self.clientVersion = clientVersion
            self.arguments = arguments
            self.passesFile = passesFile
        }
    }

    public enum Frame: Equatable {
        case request(Request)
        case stdout(Data)
        case stderr(Data)
        case exit(Int32)
        case rejected(String)
    }

    enum DecodeError: Error {
        case unknownKind
        case oversizedPayload
        case invalidPayload
    }

    private enum Kind: UInt8 {
        // Tag 2 was used to forward signals to the spawned CLI.
        case request = 1, stdout = 3, stderr, exit, rejected
    }

    private static let maximumPayload = 64 * 1024 * 1024
    private static let headerLength = 5

    public static func encode(_ frame: Frame) -> Data {
        let kind: Kind
        let payload: Data
        switch frame {
        case .request(let request):
            kind = .request
            // Request contains only JSON-encodable strings, integers and a boolean.
            payload = try! JSONEncoder().encode(request)
        case .stdout(let output):
            (kind, payload) = (.stdout, output)
        case .stderr(let output):
            (kind, payload) = (.stderr, output)
        case .exit(let status):
            (kind, payload) = (.exit, encodeInteger(UInt32(bitPattern: status)))
        case .rejected(let reason):
            (kind, payload) = (.rejected, Data(reason.utf8))
        }
        var frame = Data([kind.rawValue])
        frame.append(encodeInteger(UInt32(payload.count)))
        frame.append(payload)
        return frame
    }

    /// Consume one complete frame, leaving a partial frame in the buffer.
    public static func decode(from buffer: inout Data) throws -> Frame? {
        guard buffer.count >= headerLength else { return nil }
        guard let kind = buffer.first.flatMap(Kind.init(rawValue:)) else { throw DecodeError.unknownKind }
        let length = Int(decodeInteger(buffer.prefix(headerLength).dropFirst()))
        guard length <= maximumPayload else { throw DecodeError.oversizedPayload }
        guard buffer.count >= headerLength + length else { return nil }
        let payload = Data(buffer.dropFirst(headerLength).prefix(length))
        let frame: Frame
        switch kind {
        case .request:
            frame = .request(try JSONDecoder().decode(Request.self, from: payload))
        case .exit:
            guard payload.count == 4 else { throw DecodeError.invalidPayload }
            frame = .exit(Int32(bitPattern: decodeInteger(payload)))
        case .stdout:
            frame = .stdout(payload)
        case .stderr:
            frame = .stderr(payload)
        case .rejected:
            guard let reason = String(data: payload, encoding: .utf8) else { throw DecodeError.invalidPayload }
            frame = .rejected(reason)
        }
        buffer.removeFirst(headerLength + length)
        return frame
    }

    private static func encodeInteger(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func decodeInteger(_ bytes: Data) -> UInt32 {
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
