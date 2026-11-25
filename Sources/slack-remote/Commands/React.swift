import ArgumentParser
import SlackRemoteCore

struct React: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("react", error: .notImplemented, result: nil as Bool?)
    }
}
