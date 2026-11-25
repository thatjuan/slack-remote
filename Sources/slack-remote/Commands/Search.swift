import ArgumentParser
import SlackRemoteCore

struct Search: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("search", error: .notImplemented, result: nil as Bool?)
    }
}
