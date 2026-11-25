import ArgumentParser
import SlackRemoteCore

struct People: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("people", error: .notImplemented, result: nil as Bool?)
    }
}
