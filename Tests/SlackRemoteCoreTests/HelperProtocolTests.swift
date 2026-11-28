import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperProtocolTests {
    @Test(arguments: [
        HelperProtocol.Frame.request(.init(clientVersion: "1.2.0", arguments: ["webkit-poc", "accounts"])),
        .stdout(Data([0, 255])), .stderr(Data()), .exit(130), .rejected("version_mismatch"),
    ])
    func roundTrips(_ frame: HelperProtocol.Frame) throws {
        var buffer = HelperProtocol.encode(frame)
        #expect(try HelperProtocol.decode(from: &buffer) == frame)
        #expect(buffer.isEmpty)
    }

    @Test func waitsForWholeFrame() throws {
        let frame = HelperProtocol.Frame.stderr(Data("error".utf8))
        let encoded = HelperProtocol.encode(frame)
        for length in 0..<encoded.count {
            let partial = Data(encoded.prefix(length))
            var buffer = partial
            #expect(try HelperProtocol.decode(from: &buffer) == nil)
            #expect(buffer == partial)
            buffer.append(encoded.dropFirst(length))
            #expect(try HelperProtocol.decode(from: &buffer) == frame)
        }
    }

    @Test func decodesFramesInOrder() throws {
        var buffer = HelperProtocol.encode(.stdout(Data([1]))) + HelperProtocol.encode(.exit(7))
        #expect(try HelperProtocol.decode(from: &buffer) == .stdout(Data([1])))
        #expect(try HelperProtocol.decode(from: &buffer) == .exit(7))
        #expect(buffer.isEmpty)
    }

    @Test func rejectsInvalidHeaders() {
        var unknownKind = Data([99, 0, 0, 0, 0])
        var oversized = Data([3, 4, 0, 0, 1])
        #expect(throws: HelperProtocol.DecodeError.unknownKind) { try HelperProtocol.decode(from: &unknownKind) }
        #expect(throws: HelperProtocol.DecodeError.oversizedPayload) { try HelperProtocol.decode(from: &oversized) }
    }
}
