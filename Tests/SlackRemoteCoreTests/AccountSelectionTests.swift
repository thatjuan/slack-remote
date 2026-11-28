import Foundation
import SlackRemoteCore
import Testing

struct AccountSelectionTests {
    private let first = TeamID("T00000001")!
    private let second = TeamID("T00000002")!
    private let unknown = TeamID("T00000003")!

    private func account(_ teams: [TeamID], state: AccountRecord.State = .active) -> AccountRecord {
        AccountRecord(id: AccountID(), teams: teams.map {
            .init(id: $0, name: "Acme", url: URL(string: "https://acme.slack.com/")!,
                  user: UserID("U00000001")!, userName: "Ada")
        }, state: state, addedAt: Date())
    }

    @Test func selectsOnlyActiveTeam() throws {
        let active = account([first])
        let signedOut = account([second], state: .signedOut)
        let selection = try AccountSelection.resolve(nil, in: [signedOut, active])
        #expect(selection.account.id == active.id)
        #expect(selection.team.id == first)
    }

    @Test func requiresExplicitTeamWhenSeveralAreActive() throws {
        let active = account([second, first])
        #expect(throws: RemoteError.teamRequired(teams: [first, second])) {
            try AccountSelection.resolve(nil, in: [active])
        }
        #expect(try AccountSelection.resolve(second, in: [active]).team.id == second)
    }

    @Test func rejectsUnknownTeam() {
        #expect(throws: RemoteError.noAccount(team: unknown)) {
            try AccountSelection.resolve(unknown, in: [account([first])])
        }
    }

    @Test func rejectsSignedOutTeam() {
        #expect(throws: RemoteError.accountSignedOut(team: "Acme")) {
            try AccountSelection.resolve(first, in: [account([first], state: .signedOut)])
        }
    }
}
