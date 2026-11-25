import ArgumentParser
import Foundation
import SlackRemoteCore

extension Inspector.Scope: ExpressibleByArgument {}

struct Inspect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print Slack's Accessibility structure.")

    @OptionGroup var options: CommandOptions
    @Option(help: "Accessibility subtree to inspect.") var scope: Inspector.Scope = .window
    @Option(help: "Maximum depth below the scope root.") var maxDepth: Int?
    @Flag(help: "Show shortcode titles on emoji images.") var emojiNames = false

    func validate() throws {
        if let maxDepth, maxDepth < 0 { throw ValidationError("--max-depth must be zero or greater.") }
    }

    func run() throws {
        try CommandSupport.run("inspect", options: options, allowOverlays: true, output: { _, result in
            try FileHandle.standardOutput.write(contentsOf: Data(result.utf8))
        }) { _, tree, _ in
            let window = try SlackWindow.currentWindow(in: tree).window
            return Inspector.describe(window, scope: scope, maxDepth: maxDepth, emojiNames: emojiNames)
        }
    }
}
