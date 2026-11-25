# slack-remote planning manifest

Issue drafts for the first milestone of `thatjuan/slack-remote`, ready to publish. Nothing here has been filed on GitHub. No implementation exists yet.

## Milestone

Title: `v0.1: Slack desktop remote MVP`

Description: the contents of [`milestone.md`](milestone.md).

## Issues

Each file under `issues/` is a complete issue body. Its first line is an HTML comment holding the title; GitHub does not render it.

| # | File | Title | In milestone | Depends on |
|---|---|---|---|---|
| 1 | [`issues/01-foundation-doctor-current-open.md`](issues/01-foundation-doctor-current-open.md) | Foundation: Swift package, Accessibility session, safety gates, and the doctor, current and open commands | yes | none |
| 2 | [`issues/02-read-visible-messages.md`](issues/02-read-visible-messages.md) | Read the messages Slack has rendered in a conversation | yes | 1 |
| 3 | [`issues/03-draft-and-send.md`](issues/03-draft-and-send.md) | Write a draft and send a message to a verified conversation | yes | 1, 2 |
| 4 | [`issues/04-optional-threads-and-reactions.md`](issues/04-optional-threads-and-reactions.md) | Optional: thread replies and reactions, where they can be targeted exactly | no | 1, 2, 3 |

```
1 foundation ──▶ 2 read ──▶ 3 draft and send ──▶ 4 threads and reactions (optional)
```

The issues refer to each other by title. After filing, the coordinator may replace those references with issue numbers.

Supporting documents: [`evidence.md`](evidence.md) records what the probes observed and what they did not. [`validation.md`](validation.md) explains how to validate the delivered CLI.

## Scope

MVP, in the milestone: `doctor`, `current`, `open`, `read`, `draft set`, `draft clear`, `send`.

Superseded for issue 4: [`next/`](next/README.md) plans the complete CLI as a second milestone and replaces issue 4's optional body with required work based on routes observed later. The rest of this section records the v0.1 view.

Optional, outside the milestone: `read --thread`, `reply`, `react`. Issue 4 starts with a structural probe and builds only the paths that can be tied to a message id. The planning probe found that the hover toolbar is absent from the tree until a message is hovered or focused, and that Slack documents no link to a message or thread, so some of these may turn out to be unsupported.

Out of scope altogether: scrolling or loading history, search, editing or deleting messages, file upload, scheduled sends, removing reactions, launching Slack, bridging from ssh into the GUI session.

## Stack decision

Swift, as one SwiftPM package that builds a single binary named `slack-remote`.

- The product is a sequence of calls into the macOS Accessibility C API, AppKit and CoreGraphics. Swift calls all three directly with typed values.
- The result is one compiled binary with no runtime to install.
- One dependency, `swift-argument-parser`, for subcommands, flags and help.
- Tests use Swift Testing, which ships with the toolchain. main-mac has Swift 6.4.2 and Xcode 27.2.
- All logic sits behind a small `UINode` protocol, so destination checks, message extraction and the send state machine are tested against fake trees without touching Slack.
- Output is JSON on stdout for every command, with a JSON error on stderr and a distinct exit status per failure class. The callers are agents, so one format is enough.
- There is no daemon, no configuration file and no database. The only files the tool writes are a lock file and a marker recording that it switched Slack's accessibility tree on.

Alternatives considered: TypeScript or Python would need a native bridge to reach `AXUIElement`, plus a runtime on every host. AppleScript and JXA go through System Events, which needs a second permission and cannot batch attribute reads. Rust would need FFI bindings for the same frameworks and is not installed on main-mac. None of the usual web stack applies, because there is no server, storage or UI.

## How each risk is handled

| Concern | Behaviour |
|---|---|
| Login session | Commands require a console GUI session and an unlocked screen, checked through `CGSessionCopyCurrentDictionary`. From ssh they fail with `no_gui_session`. |
| Accessibility permission | Read without prompting. When absent the command stops with `accessibility_not_trusted`. The tool never requests or grants it. The permission belongs to the app that launched the tool. |
| Slack's hidden tree | Slack exposes web content only after `AXManualAccessibility` is set on its application element. The tool sets it, waits for the tree to settle, and sets it back on every exit path including signals. A marker file lets the next run clean up after a killed one. If another assistive tool had already enabled the tree, the tool leaves the mode alone. |
| Exact destination | A conversation is verified by the team and conversation ids in Slack's own web area URL, cross-checked against the selected sidebar row. Names and titles are never used. |
| Timeouts | One `--timeout` deadline per command, default 15 s. Every wait is a bounded poll. Each Accessibility call has a 2 s messaging timeout. |
| UI version drift | Elements are found by role, subrole, DOM class and DOM id, never by localised text. Each locator must match exactly once; otherwise the command stops with `ui_drift`. An untested Slack version adds a warning and the structure checks remain the gate. |
| Existing drafts | A composer holding anything other than the exact requested text stops the command with `draft_conflict`. Drafts are never replaced or appended to. `draft clear` removes only text the caller names exactly. |
| Competing focus | A command that would navigate or write stops with `slack_in_use` when Slack is frontmost and the user gave input within 30 s, unless `--interrupt` is passed. Links are opened without activating Slack, and the previous frontmost app is restored if Slack takes focus anyway. Before the send press the destination, composer text and send button are all re-read. |
| Concurrent invocations | One `flock` lock for the whole command. A second invocation waits until its deadline and then fails with `busy`. |
| Recovery | A failure after a write leaves the text as a draft in the verified conversation and reports `draftLeft: true`. Re-running the same `send` resumes from the identical draft. The send button is pressed once and never retried; an outcome that cannot be established is reported as `send_unconfirmed`. |
| Unsafe text | Slash commands, the `+:emoji:` shortcut and `@channel`-style broadcasts are refused before Slack is touched; broadcasts can be allowed with a flag. |

## Implementation waves

One worker at a time, one pull request per issue, each branched from `main` after the previous one merges.

| Wave | Issue | Why it waits |
|---|---|---|
| 1 | 1 | Everything else uses its types, locators and gates. |
| 2 | 2 | Needs wave 1. |
| 3 | 3 | Confirms a send by reading the new message, so it uses wave 2's `MessageReader`. |
| later | 4 | Optional. Reuses the composer and sender from wave 3. |

Issues 2 and 3 were kept in sequence. Running them in parallel would save little and would have both workers editing `Main.swift`, `Locators.swift` and `README.md`.

## File ownership

| Issue | Creates | May modify |
|---|---|---|
| 1 | `Package.swift`, `.gitignore`, `README.md`, `Sources/slack-remote/{Main,CommandSupport}.swift`, `Sources/slack-remote/Commands/{Doctor,Current,Open}.swift`, `Sources/SlackRemoteCore/{UINode,AXNode,Environment,SlackApp,CommandLock,Poll,Locators,Destination,SlackWindow,Navigator,RemoteError}.swift`, `Tests/SlackRemoteCoreTests/Support/{FakeNode,SlackFixture}.swift`, `Tests/SlackRemoteCoreTests/{Destination,SlackWindow,Navigator,SlackApp}Tests.swift`, `docs/validation/foundation.md` | nothing else exists yet |
| 2 | `Sources/slack-remote/Commands/Read.swift`, `Sources/SlackRemoteCore/MessageReader.swift`, `Tests/SlackRemoteCoreTests/MessageReaderTests.swift`, `Tests/SlackRemoteCoreTests/Support/MessageFixtures.swift`, `docs/validation/read.md` | `Main.swift` (subcommand list), `Locators.swift` (Messages section), `README.md` (read section) |
| 3 | `Sources/slack-remote/Commands/{Draft,Send}.swift`, `Sources/SlackRemoteCore/{MessageText,Composer,Sender}.swift`, `Tests/SlackRemoteCoreTests/{MessageText,Composer,Sender}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/ComposerFixtures.swift`, `docs/validation/write.md` | `Main.swift` (subcommand list), `Locators.swift` (Composer section), `README.md` (draft and send sections) |
| 4 | `Sources/slack-remote/Commands/{Reply,React}.swift`, `Sources/SlackRemoteCore/{ThreadView,Reactions}.swift`, `Tests/SlackRemoteCoreTests/{ThreadView,Reactions}Tests.swift`, `Tests/SlackRemoteCoreTests/Support/ThreadFixtures.swift`, `docs/validation/threads-reactions.md` | `Main.swift`, `Commands/Read.swift`, `Locators.swift` (new section), `Composer.swift`, `Sender.swift`, `README.md` |

The `planning/` directory belongs to this planning branch. Implementation workers do not edit it.

## Publishing

From a checkout of this branch on a machine with an authenticated `gh`:

```sh
gh api repos/thatjuan/slack-remote/milestones \
  -f title='v0.1: Slack desktop remote MVP' \
  -F description=@planning/milestone.md

gh issue create --repo thatjuan/slack-remote \
  --milestone 'v0.1: Slack desktop remote MVP' \
  --title 'Foundation: Swift package, Accessibility session, safety gates, and the doctor, current and open commands' \
  --body-file planning/issues/01-foundation-doctor-current-open.md

gh issue create --repo thatjuan/slack-remote \
  --milestone 'v0.1: Slack desktop remote MVP' \
  --title 'Read the messages Slack has rendered in a conversation' \
  --body-file planning/issues/02-read-visible-messages.md

gh issue create --repo thatjuan/slack-remote \
  --milestone 'v0.1: Slack desktop remote MVP' \
  --title 'Write a draft and send a message to a verified conversation' \
  --body-file planning/issues/03-draft-and-send.md

gh issue create --repo thatjuan/slack-remote \
  --title 'Optional: thread replies and reactions, where they can be targeted exactly' \
  --body-file planning/issues/04-optional-threads-and-reactions.md
```

## Inputs needed before implementation

- A disposable Slack destination from Juan: a team id and conversation id, a second conversation for the draft persistence check, and optionally a DM with its user id. Without it, workers build and unit-test everything and run only the read-only live checks. The write-method spike that opens issue 3 cannot run without it, so issue 3 would stop there and report.
- Explicit permission for live sends (`SLACK_REMOTE_TEST_ALLOW_SEND=1`), if Juan wants `send` exercised against the disposable destination. Without it `send` is validated against fake trees only.
- The Accessibility permission for whichever app launches the implementation worker on main-mac. The planning probe ran under a process that already had it.

## Known gaps in the evidence

- No link was opened, nothing was pressed and nothing was typed during planning, by instruction. The first observations of navigation, composer writes and sending happen inside issues 1 and 3 under the disposable-destination rule.
- Slack 4.52.178 on jmbp has only the earlier read-only summary. The detailed structure in the issues comes from 4.53.292 on main-mac.
- Enterprise Grid, a signed-out client, several Slack windows, and Slack hidden or minimised were not observed.
