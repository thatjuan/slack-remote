import ArgumentParser
import Darwin
import Foundation
import SlackRemoteCore

/// Opens the source locally and passes its descriptor to the helper.
struct Upload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Share a file in a Slack conversation or thread.")

    @OptionGroup var options: WriteOptions
    @Option(help: "Path to a regular local file.") var file: String
    @Option(help: "Caption to send with the file.") var text: String?
    @Option(help: "The thread root's Slack message timestamp.", transform: writeTimestamp) var thread: String?
    @Option(help: "Maximum file size in bytes, up to 1,000,000,000.") var maxSize = UploadRequest.defaultMaxSize

    func validate() throws {
        guard (1...UploadRequest.maximumMaxSize).contains(maxSize) else {
            throw ValidationError("--max-size must be between 1 and 1,000,000,000 bytes.")
        }
    }

    func run() throws {
        let path = (file as NSString).expandingTildeInPath
        let request = UploadRequest(target: try options.destination(), fileName: (path as NSString).lastPathComponent,
                                    maxSize: maxSize, text: text, thread: thread, dryRun: options.dryRun)
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        defer { if fd >= 0 { close(fd) } }
        throw ExitCode(HelperClient.call(command: "upload", operation: .upload(request), timeout: options.command.timeout,
                                         file: fd >= 0 ? fd : nil))
    }
}
