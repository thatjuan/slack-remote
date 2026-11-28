import Foundation
import os
@testable import SlackRemoteCore
import Testing

struct UserDirectoryTests {
    @Test func cachesNamesForAnHourAndUsesTheFirstNonemptyField() async throws {
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"user":{"id":"U00000002","name":"ada","profile":{"display_name":"Ada","real_name":"Ada Example"}}}"#,
            #"{"ok":true,"user":{"id":"U00000002","name":"ada","profile":{"display_name":"","real_name":"Ada Updated"}}}"#)
        let user = UserID("U00000002")!
        let clock = OSAllocatedUnfairLock(initialState: Date())
        let directory = UserDirectory(api: fixtures.api, now: { clock.withLock { $0 } })

        #expect(try await directory.names(for: [user]) == [user: "Ada"])
        clock.withLock { $0.addTimeInterval(3599) }
        #expect(try await directory.names(for: [user]) == [user: "Ada"])
        #expect(await fixtures.transport.requests.count == 1)

        clock.withLock { $0.addTimeInterval(1) }
        #expect(try await directory.names(for: [user]) == [user: "Ada Updated"])
        #expect(await fixtures.transport.requests.count == 2)
    }

    @Test func missingUserDoesNotDiscardOtherNames() async throws {
        let fixtures = ReadCommandFixtures(
            #"{"ok":true,"members":[{"id":"U00000002","name":"ada","profile":{"display_name":"","real_name":""}}]}"#,
            #"{"ok":false,"error":"user_not_found"}"#)
        let known = UserID("U00000002")!
        let missing = UserID("U00000003")!
        _ = try await PeopleRequest().run(in: fixtures.context())
        #expect(try await fixtures.directory.names(for: [known, missing]) == [known: "ada"])
        #expect(await fixtures.transport.requests.last?.params == ["user": missing.rawValue])
    }
}
