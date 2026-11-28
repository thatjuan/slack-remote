import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperProtocolTests {
    @Test(arguments: [
        HelperProtocol.Frame.call(.init(clientVersion: "2.0.0", command: "whoami",
                                        operation: .whoami(WhoamiRequest(team: TeamID("T02R8SSJGCU"))),
                                        timeout: 20, configPath: "/tmp/example.json")),
        .signal(SIGINT),
        .stdout(Data([0, 255])), .stderr(Data()), .exit(130), .rejected("version_mismatch"),
    ])
    func roundTrips(_ frame: HelperProtocol.Frame) throws {
        var buffer = try HelperProtocol.encode(frame)
        #expect(try HelperProtocol.decode(from: &buffer) == frame)
        #expect(buffer.isEmpty)
    }

    @Test func waitsForWholeFrame() throws {
        let frame = HelperProtocol.Frame.stderr(Data("error".utf8))
        let encoded = try HelperProtocol.encode(frame)
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
        var buffer = try HelperProtocol.encode(.stdout(Data([1]))) + HelperProtocol.encode(.exit(7))
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

    @Test(arguments: [
        SlackRemoteCore.Operation.doctor(DoctorRequest()),
        .whoami(WhoamiRequest(team: TeamID("T04JKELQC"))),
        .accountsList(AccountsListRequest()),
        .accountsAdd(AccountsAddRequest(wait: true)),
        .accountsRemove(AccountsRemoveRequest(id: AccountID())),
    ])
    func roundTripsOperation(_ operation: SlackRemoteCore.Operation) throws {
        let payload = try JSONEncoder().encode(operation)
        #expect(try JSONDecoder().decode(SlackRemoteCore.Operation.self, from: payload) == operation)
    }
}
