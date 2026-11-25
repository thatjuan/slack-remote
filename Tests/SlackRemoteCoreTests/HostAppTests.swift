import Darwin
@testable import SlackRemoteCore
import Testing

struct HostAppTests {
    @Test func findsTerminalThroughShellAndLogin() {
        let parents: [pid_t: pid_t] = [40: 30, 30: 20, 20: 1]
        let executables: [pid_t: String] = [
            40: "/bin/zsh",
            30: "/usr/bin/login",
            20: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        ]
        #expect(HostApp.bundlePath(startingAt: 40, parent: { parents[$0] }, executablePath: { executables[$0] })
                == "/System/Applications/Utilities/Terminal.app")
    }

    @Test func findsOutermostElectronBundle() {
        let parents: [pid_t: pid_t] = [40: 30, 30: 1]
        let executables: [pid_t: String] = [
            40: "/bin/zsh",
            30: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
        ]
        #expect(HostApp.bundlePath(startingAt: 40, parent: { parents[$0] }, executablePath: { executables[$0] })
                == "/Applications/Visual Studio Code.app")
    }

    @Test func returnsNoHostOutsideAnApp() {
        let parents: [pid_t: pid_t] = [40: 30, 30: 20, 20: 1]
        let executables: [pid_t: String] = [40: "/bin/zsh", 30: "/opt/homebrew/bin/tmux", 20: "/usr/sbin/sshd"]
        #expect(HostApp.bundlePath(startingAt: 40, parent: { parents[$0] }, executablePath: { executables[$0] }) == nil)
    }

    @Test func stopsOnAParentCycle() {
        let parents: [pid_t: pid_t] = [50: 60, 60: 50]
        var visited: [pid_t] = []
        #expect(HostApp.bundlePath(startingAt: 50, parent: { parents[$0] }, executablePath: {
            visited.append($0)
            return "/bin/zsh"
        }) == nil)
        #expect(visited == [50, 60])
    }

    @Test func stopsAfter64Ancestors() {
        var visits = 0
        #expect(HostApp.bundlePath(startingAt: 100, parent: { $0 + 1 }, executablePath: { _ in
            visits += 1
            return nil
        }) == nil)
        #expect(visits == 64)
    }

    @Test func ignoresNonBundleComponents() {
        #expect(HostApp.outermostBundle(in: "/Users/x/my.apple/bin/tool") == nil)
    }
}
