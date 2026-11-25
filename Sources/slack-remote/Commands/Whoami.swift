import ArgumentParser
import SlackRemoteCore

struct Whoami: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Identify the Slack account in the current workspace.")

    @OptionGroup var options: CommandOptions
    @Flag(help: "Save or replace this workspace's account in the private config.") var save = false

    func run() throws {
        try CommandSupport.run("whoami", options: options) { _, tree, deadline in
            var config = save ? try Config.load() ?? Config() : Config()
            let account = try Account.identify(in: tree, deadline: deadline)
            if save {
                config.saveAccount(account)
                try config.save()
            }
            return account
        }
    }
}
