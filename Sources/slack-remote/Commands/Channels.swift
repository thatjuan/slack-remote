import ArgumentParser
import SlackRemoteCore

struct Channels: ParsableCommand {
    func run() throws {
        try CommandSupport.fail("channels", error: .notImplemented, result: nil as Bool?)
    }
}
