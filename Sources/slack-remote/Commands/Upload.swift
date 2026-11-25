import ArgumentParser
import SlackRemoteCore

struct Upload: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("upload", error: .notImplemented, result: nil as Bool?)
    }
}
