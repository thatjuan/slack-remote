import ArgumentParser
import Foundation
import SlackRemoteCore

struct Accounts: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Manage accounts in SlackRemote.app.",
                                                    subcommands: [List.self, Add.self, Remove.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List Slack accounts and workspaces.")

        @OptionGroup var options: CommandOptions

        func run() throws {
            throw ExitCode(HelperClient.call(command: "accounts list", operation: .accountsList(AccountsListRequest()),
                                             timeout: options.timeout))
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a Slack sign-in window.")

        @Flag(help: "Wait for the window to record a workspace or close.") var wait = false
        @Option(help: "Time limit for the command in seconds.") var timeout: Double = 300

        func validate() throws {
            try CommandOptions.validateTimeout(timeout)
        }

        func run() throws {
            throw ExitCode(HelperClient.call(command: "accounts add", operation: .accountsAdd(AccountsAddRequest(wait: wait)),
                                             timeout: timeout))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove a Slack account from this Mac.")

        @OptionGroup var options: CommandOptions
        @Argument(help: "Account ID from accounts list.", transform: { raw in
            guard let uuid = UUID(uuidString: raw) else { throw ValidationError("Expected an account UUID.") }
            return AccountID(rawValue: uuid)
        }) var accountID: AccountID

        func run() throws {
            throw ExitCode(HelperClient.call(command: "accounts remove", operation: .accountsRemove(AccountsRemoveRequest(id: accountID)),
                                             timeout: options.timeout))
        }
    }
}
