import ArgumentParser
import SlackRemoteCore

struct Members: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("members", error: .notImplemented, result: nil as Bool?)
    }
}
