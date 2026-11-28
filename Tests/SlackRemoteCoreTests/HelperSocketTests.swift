import Darwin
import Foundation
@testable import SlackRemoteCore
import Testing

struct HelperSocketTests {
    @Test func passesAnOpenFileDescriptor() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let sender = try HelperSocket(adopting: descriptors[0])
        let receiver = try HelperSocket(adopting: descriptors[1])

        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bytes = Data([0, 42, 255])
        try bytes.write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let source = try FileHandle(forReadingFrom: path)
        defer { try? source.close() }
        try FileManager.default.removeItem(at: path)
        let request = HelperProtocol.Request(clientVersion: "test", arguments: [], passesFile: true)
        try sender.send(.request(request), passing: source.fileDescriptor)

        let (received, descriptor) = try #require(try receiver.receiveRequest())
        let file = FileHandle(fileDescriptor: try #require(descriptor), closeOnDealloc: true)
        defer { try? file.close() }
        #expect(received == request)
        #expect(try file.readToEnd() == bytes)
        #expect(fcntl(file.fileDescriptor, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    }
}
