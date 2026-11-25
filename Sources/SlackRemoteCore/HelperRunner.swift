import Darwin
import Foundation

struct HelperRunner {
    static let signals = [SIGINT, SIGTERM, SIGHUP]

    private let pid: pid_t
    private let stdout: Int32
    private let stderr: Int32

    static func spawn(at binary: URL, request: HelperProtocol.Request, file: Int32?, version: String) throws
        -> HelperRunner {
        guard !request.workingDirectory.utf8.contains(0),
              request.configPath?.utf8.contains(0) != true,
              request.arguments.allSatisfy({ !$0.utf8.contains(0) }) else { throw POSIXError(.EINVAL) }
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        // Concurrent requests can open descriptors while the runner is spawning.
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
                                                            | POSIX_SPAWN_SETSIGMASK)))
        var defaultSignals = sigset_t()
        var signalMask = sigset_t()
        sigemptyset(&defaultSignals)
        sigemptyset(&signalMask)
        for number in signals { sigaddset(&defaultSignals, number) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaultSignals))
        try check(posix_spawnattr_setsigmask(&attributes, &signalMask))

        let out = try makePipe()
        var success = false
        defer {
            close(out.write)
            if !success { close(out.read) }
        }
        let err = try makePipe()
        defer {
            close(err.write)
            if !success { close(err.read) }
        }

        try check(posix_spawn_file_actions_addchdir_np(&actions, request.workingDirectory))
        try check(posix_spawn_file_actions_adddup2(&actions, out.write, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, err.write, STDERR_FILENO))
        if let file {
            try check(posix_spawn_file_actions_adddup2(&actions, file, HelperForwarding.uploadDescriptor))
        }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))

        var environment = ProcessInfo.processInfo.environment
        environment["SLACK_REMOTE_NO_HELPER"] = "1"
        environment["SLACK_REMOTE_VIA_HELPER"] = version
        environment["SLACK_REMOTE_CONFIG"] = request.configPath
        var pid: pid_t = 0
        try withCStrings([binary.path] + request.arguments) { argv in
            try withCStrings(environment.map { "\($0.key)=\($0.value)" }) { envp in
                try check(posix_spawn(&pid, binary.path, &actions, &attributes, argv, envp))
            }
        }
        success = true
        return Self(pid: pid, stdout: out.read, stderr: err.read)
    }

    func stream(to connection: HelperSocket) -> Int32 {
        let queue = DispatchQueue.global(qos: .userInitiated)
        let forwarding = DispatchGroup()
        queue.async(group: forwarding) { stream(stdout, to: connection, as: HelperProtocol.Frame.stdout) }
        queue.async(group: forwarding) { stream(stderr, to: connection, as: HelperProtocol.Frame.stderr) }
        queue.async(group: forwarding) {
            while case .signal(let number) = try? connection.receive(), Self.signals.contains(number) {
                kill(pid, number)
            }
            kill(pid, SIGTERM)
        }

        // Keep the PID reserved until the signal reader has stopped.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
        shutdown(connection.descriptor, SHUT_RD)
        forwarding.wait()
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, 0) } while result == -1 && errno == EINTR
        guard result == pid else { return 1 }
        let terminationSignal = status & 0x7f
        return terminationSignal == 0 ? (status >> 8) & 0xff : 128 + terminationSignal
    }

    private func stream(_ fd: Int32, to connection: HelperSocket, as frame: (Data) -> HelperProtocol.Frame) {
        defer { close(fd) }
        var buffer = Data(count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return }
            do {
                try connection.send(frame(buffer.prefix(count)))
            } catch {
                connection.disconnect()
                return
            }
        }
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { throw HelperSocket.systemError() }
        for index in ends.indices where ends[index] < 3 {
            let replacement = fcntl(ends[index], F_DUPFD_CLOEXEC, 3)
            guard replacement >= 0 else {
                let error = HelperSocket.systemError()
                for fd in ends { close(fd) }
                throw error
            }
            close(ends[index])
            ends[index] = replacement
        }
        return (ends[0], ends[1])
    }

    private static func check(_ error: Int32) throws {
        if error != 0 { throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO) }
    }

    private static func withCStrings<T>(_ strings: [String],
                                         _ work: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T)
        throws -> T {
        var pointers = strings.map { strdup($0) }
        defer { for pointer in pointers { free(pointer) } }
        guard pointers.allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        pointers.append(nil)
        return try work(&pointers)
    }
}
