import ArgumentParser
import SlackRemoteCore

struct Reply: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("reply", error: .notImplemented, result: nil as Bool?)
    }
}
