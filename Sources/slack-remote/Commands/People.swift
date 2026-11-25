import ArgumentParser
import SlackRemoteCore

struct People: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the Slack workspace people directory.")

    @OptionGroup var options: CommandOptions
    @OptionGroup var listing: ListingOptions
    @OptionGroup var workspace: ListingWorkspace

    func run() throws {
        let unavailable: (SlackApp, SlackTree, PageBounds) throws -> (MemberListingResult, StopReason) = { _, _, _ in
            throw RemoteError.unsupportedDestination
        }
        try listing.run("people", options: options, work: unavailable)
    }
}
